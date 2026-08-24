const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      revealObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });

document.querySelectorAll('.reveal').forEach((el) => revealObserver.observe(el));

document.querySelectorAll('.use-tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    const target = tab.dataset.case;
    document.querySelectorAll('.use-tab').forEach((item) => {
      const active = item === tab;
      item.classList.toggle('active', active);
      item.setAttribute('aria-selected', String(active));
    });
    document.querySelectorAll('.use-copy').forEach((panel) => {
      panel.classList.toggle('active', panel.dataset.panel === target);
    });
  });
});
