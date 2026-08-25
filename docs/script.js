const revealElements = [...document.querySelectorAll('.reveal')];
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

if ('IntersectionObserver' in window && !reduceMotion) {
  const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('visible');
      entry.target.classList.remove('reveal-pending');
      revealObserver.unobserve(entry.target);
    });
  }, { threshold: 0.12 });

  revealElements.forEach((element) => {
    element.classList.add('reveal-pending');
    revealObserver.observe(element);
  });
}

const siteHeader = document.querySelector('.site-header');
const navToggle = document.querySelector('.nav-toggle');
const mainNavigation = document.querySelector('#main-navigation');

const setNavigationOpen = (open) => {
  if (!siteHeader || !navToggle) return;
  siteHeader.classList.toggle('nav-open', open);
  navToggle.setAttribute('aria-expanded', String(open));
  navToggle.setAttribute('aria-label', open ? 'Close navigation menu' : 'Open navigation menu');
};

navToggle?.addEventListener('click', () => {
  setNavigationOpen(navToggle.getAttribute('aria-expanded') !== 'true');
});

mainNavigation?.addEventListener('click', (event) => {
  if (event.target.closest('a')) setNavigationOpen(false);
});

document.addEventListener('click', (event) => {
  if (siteHeader?.classList.contains('nav-open') && !siteHeader.contains(event.target)) {
    setNavigationOpen(false);
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && siteHeader?.classList.contains('nav-open')) {
    setNavigationOpen(false);
    navToggle?.focus();
  }
});

window.addEventListener('resize', () => {
  if (window.innerWidth > 980) setNavigationOpen(false);
});

const useCaseTabs = [...document.querySelectorAll('.use-tab')];
const useCasePanels = [...document.querySelectorAll('.use-copy[role="tabpanel"]')];

const activateUseCase = (nextTab, moveFocus = false) => {
  const target = nextTab?.dataset.case;
  if (!target) return;

  useCaseTabs.forEach((tab) => {
    const active = tab === nextTab;
    tab.classList.toggle('active', active);
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
  });

  useCasePanels.forEach((panel) => {
    const active = panel.dataset.panel === target;
    panel.classList.toggle('active', active);
    panel.hidden = !active;
  });

  if (moveFocus) {
    nextTab.focus();
    nextTab.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
};

useCaseTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => activateUseCase(tab));
  tab.addEventListener('keydown', (event) => {
    let nextIndex = null;

    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
      nextIndex = (index + 1) % useCaseTabs.length;
    } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
      nextIndex = (index - 1 + useCaseTabs.length) % useCaseTabs.length;
    } else if (event.key === 'Home') {
      nextIndex = 0;
    } else if (event.key === 'End') {
      nextIndex = useCaseTabs.length - 1;
    }

    if (nextIndex === null) return;
    event.preventDefault();
    activateUseCase(useCaseTabs[nextIndex], true);
  });
});
