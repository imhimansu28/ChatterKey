const siteHeader = document.querySelector('.site-header');
const navToggle = document.querySelector('.nav-toggle');
const mainNavigation = document.querySelector('#main-navigation');

const setNavigationOpen = (open) => {
  if (!siteHeader || !navToggle) return;
  siteHeader.classList.toggle('nav-open', open);
  navToggle.setAttribute('aria-expanded', String(open));
  navToggle.textContent = open ? 'Close' : 'Menu';
  navToggle.setAttribute('aria-label', open ? 'Close navigation menu' : 'Open navigation menu');
};

if (siteHeader && navToggle && mainNavigation) {
  navToggle.disabled = false;
  navToggle.addEventListener('click', () => {
    setNavigationOpen(navToggle.getAttribute('aria-expanded') !== 'true');
  });
  mainNavigation.addEventListener('click', (event) => {
    if (event.target.closest('a')) setNavigationOpen(false);
  });
  document.addEventListener('click', (event) => {
    if (siteHeader.classList.contains('nav-open') && !siteHeader.contains(event.target)) {
      setNavigationOpen(false);
    }
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && siteHeader.classList.contains('nav-open')) {
      setNavigationOpen(false);
      navToggle.focus();
    }
  });
  window.matchMedia('(max-width: 800px)').addEventListener('change', () => setNavigationOpen(false));
}
