#!/usr/bin/env python3
"""Build the shared-core Android APK using local, pinned CLI tools.

No SDK, NDK, IDE or emulator installation is performed here. Gradle may fetch
pinned build dependencies. A conservative storage guard includes tools/caches,
Android source/build output and reserves headroom below the approved 10 GB cap.
"""
from pathlib import Path
import os
import hashlib
import zipfile
import re
import shutil
import signal
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / '.build/android-tools'
NATIVE = ROOT / '.build/android-native'
SDK = TOOLS / 'swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android'
NDK = TOOLS / 'ndk/android-ndk-r27d/toolchains/llvm/prebuilt/darwin-x86_64'
SWIFT = TOOLS / 'swift-toolchain/usr/bin'
BUDGET = 9_600_000_000  # Stop early; leave 400 MB for writes already in flight.


def used_bytes():
    paths = [p for p in [TOOLS, ROOT/'.build/android-swift', NATIVE, ROOT/'apps/android', ROOT/'.build/android-host-tests'] if p.exists()]
    result = subprocess.run(['du', '-sk', *map(str, paths)], text=True, capture_output=True, env={**os.environ, 'LC_ALL': 'C'})
    # Gradle atomically renames cache entries during a scan. Ignore only vanished files.
    if result.returncode and any('No such file or directory' not in line for line in result.stderr.splitlines()):
        raise RuntimeError(result.stderr)
    totals = result.stdout.splitlines()
    if len(totals) != len(paths):
        raise RuntimeError('Could not measure every Android budget directory.')
    return sum(int(line.split()[0]) * 1024 for line in totals)


def check_budget():
    used = used_bytes()
    if used >= BUDGET or shutil.disk_usage(ROOT).free < 2_000_000_000:
        raise RuntimeError(f'Android storage guard stopped the build: {used / 1e9:.2f} GB used; hard limit 10 GB.')
    return used


def run(command, env):
    check_budget()
    process = subprocess.Popen(list(map(str, command)), cwd=ROOT, env=env, start_new_session=True)
    try:
        while process.poll() is None:
            check_budget()
            time.sleep(0.5)
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, command)
    except BaseException:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        raise


def verify_release(apk, env):
    tools = TOOLS/'sdk/build-tools/36.0.0'
    signature = subprocess.check_output([str(tools/'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], env=env, text=True)
    if 'CN=Android Debug' in signature:
        raise RuntimeError('Release APK is signed with a debug certificate.')
    run([tools/'zipalign', '-c', '-P', '16', '4', apk], env)
    manifest = subprocess.check_output([str(tools/'aapt'), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'], text=True)
    for flag in ('debuggable', 'testOnly'):
        if re.search(r'android:' + flag + r'[^\n]*=\(type 0x12\)0xffffffff', manifest):
            raise RuntimeError(f'Release APK unexpectedly enables {flag}.')
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        for asset in ('assets/licenses.txt', 'assets/privacy.txt'):
            if asset not in names or archive.getinfo(asset).file_size < 100:
                raise RuntimeError('Missing bundled document: ' + asset)
        if any(name.endswith(('.jks', '.keystore', '.properties')) and 'META-INF/' not in name for name in names):
            raise RuntimeError('Unexpected signing/configuration file in release APK.')
        native = [name for name in names if name.startswith('lib/') and name.endswith('.so')]
        if len(native) != 19 or any(not name.startswith('lib/arm64-v8a/') for name in native):
            raise RuntimeError('Unexpected native runtime inventory; review dependencies and notices.')
        for name in native:
            library = archive.read(name)
            if library[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', library, 18)[0] != 183:
                raise RuntimeError('Not an ARM64 ELF library: ' + name)
            offset = struct.unpack_from('<Q', library, 32)[0]
            stride, count = struct.unpack_from('<HH', library, 54)
            loads = 0
            for i in range(count):
                header = offset + i * stride
                if struct.unpack_from('<I', library, header)[0] != 1:
                    continue
                loads += 1
                file_offset, address = struct.unpack_from('<QQ', library, header + 8)
                alignment = struct.unpack_from('<Q', library, header + 48)[0]
                if alignment < 16384 or file_offset % 16384 != address % 16384:
                    raise RuntimeError('Native library is not 16 KB page compatible: ' + name)
            if not loads:
                raise RuntimeError('Native library has no loadable segments: ' + name)
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    apk.with_suffix('.apk.sha256').write_text(digest + '  ' + apk.name + '\n')
    apk.with_suffix('.apk.signing.txt').write_text(signature)
    print('Release verified: non-debug signing/manifest, 16 KB ZIP/ELF alignment, runtime inventory and bundled documents.')


def main():
    jdk = next(TOOLS.glob('jdk/*/Contents/Home'), None)
    if not jdk or not (SWIFT/'swift').exists():
        raise RuntimeError('Local tools are missing. See apps/android/README.md; do not install an emulator.')
    env = os.environ.copy()
    env.update(JAVA_HOME=str(jdk), ANDROID_HOME=str(TOOLS/'sdk'), ANDROID_SDK_ROOT=str(TOOLS/'sdk'),
               ANDROID_USER_HOME=str(TOOLS/'android-user'), GRADLE_USER_HOME=str(TOOLS/'gradle-cache'))
    env['PATH'] = str(jdk/'bin') + os.pathsep + str(SWIFT) + os.pathsep + env['PATH']
    run([SWIFT/'swift', 'build', '--swift-sdks-path', TOOLS/'swift-sdks', '--swift-sdk', 'aarch64-unknown-linux-android28',
         '--product', 'ChatterKeyAndroid', '--scratch-path', ROOT/'.build/android-swift', '-c', 'release', '-j', '2', '-Xswiftc', '-warnings-as-errors'], env)
    output = NATIVE/'jniLibs/arm64-v8a'
    if output.exists():
        shutil.rmtree(output)  # Only generated native payloads, never source or user files.
    output.mkdir(parents=True)
    shutil.copy2(ROOT/'.build/android-swift/aarch64-unknown-linux-android28/release/libChatterKeyAndroid.so', output)
    run([SWIFT/'clang', '--target=aarch64-linux-android28', '--sysroot='+str(NDK/'sysroot'), '-resource-dir='+str(NDK/'lib/clang/18'), '-fPIC', '-shared',
         '-Wall', '-Wextra', '-Werror', ROOT/'apps/android/app/src/main/cpp/bridge.c', '-L'+str(output), '-lChatterKeyAndroid',
         '-fuse-ld=lld', '-Wl,-z,max-page-size=16384', '-Wl,-rpath,$ORIGIN', '-o', output/'libchatterkey_jni.so'], env)
    libraries = {p.name: p for p in (SDK/'swift-resources/usr/lib/swift-aarch64/android').rglob('*.so')}
    libraries['libc++_shared.so'] = NDK/'sysroot/usr/lib/aarch64-linux-android/libc++_shared.so'
    system = {'libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libandroid.so', 'libz.so'}
    pending = list(output.glob('*.so'))
    seen = set()
    while pending:
        library = pending.pop()
        if library.name in seen:
            continue
        seen.add(library.name)
        metadata = subprocess.check_output([str(NDK/'bin/llvm-readelf'), '-d', str(library)], text=True)
        for name in re.findall(r'\(NEEDED\).*\[(.*?)\]', metadata):
            if name in system or (output/name).exists():
                continue
            if name not in libraries:
                raise RuntimeError('Unresolved Android native dependency: ' + name)
            if check_budget() + libraries[name].stat().st_size >= BUDGET:
                raise RuntimeError('Native runtime copy would exceed the storage guard.')
            shutil.copy2(libraries[name], output/name)
            pending.append(output/name)
    for library in output.glob('*.so'):
        run([NDK/'bin/llvm-strip', '--strip-debug', library], env)
    tasks = sys.argv[1:] or ['assembleDebug', 'testDebugUnitTest', 'lintDebug']
    run([TOOLS/'gradle-8.13/bin/gradle', '-p', ROOT/'apps/android', '--no-daemon', '--console=plain', *tasks], env)
    print(f'Android footprint: {used_bytes()/1e9:.2f} GB; hard limit 10 GB.')
    for variant in ('debug', 'release'):
        if any(task.split(':')[-1] == 'assemble' + variant.title() for task in tasks):
            apk = ROOT/f'apps/android/app/build/outputs/apk/{variant}/app-{variant}.apk'
            if variant == 'release':
                verify_release(apk, env)
            print('APK:', apk)


if __name__ == '__main__':
    main()
