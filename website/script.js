const menuButton = document.querySelector("[data-menu-button]");
const mobileNavigation = document.querySelector("[data-mobile-navigation]");

if (menuButton && mobileNavigation) {
  menuButton.addEventListener("click", () => {
    const open = menuButton.getAttribute("aria-expanded") === "true";
    menuButton.setAttribute("aria-expanded", String(!open));
    menuButton.setAttribute("aria-label", open ? "Open navigation" : "Close navigation");
    mobileNavigation.classList.toggle("is-open", !open);
  });

  mobileNavigation.addEventListener("click", (event) => {
    if (event.target instanceof HTMLAnchorElement) {
      menuButton.setAttribute("aria-expanded", "false");
      menuButton.setAttribute("aria-label", "Open navigation");
      mobileNavigation.classList.remove("is-open");
    }
  });
}

const formatButtons = [...document.querySelectorAll("[data-format]")];
const paperViews = [...document.querySelectorAll("[data-paper]")];

formatButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const selected = button.dataset.format;

    formatButtons.forEach((candidate) => {
      const active = candidate === button;
      candidate.classList.toggle("is-active", active);
      candidate.setAttribute("aria-pressed", String(active));
    });

    paperViews.forEach((view) => {
      const active = view.dataset.paper === selected;
      view.hidden = !active;
      view.classList.toggle("is-active", active);
    });
  });
});

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const hero = document.querySelector(".hero");

function updateHeroShift() {
  if (!hero || prefersReducedMotion.matches) return;
  const progress = Math.min(window.scrollY / Math.max(hero.offsetHeight, 1), 1);
  document.documentElement.style.setProperty("--scroll-shift", progress.toFixed(3));
}

window.addEventListener("scroll", updateHeroShift, { passive: true });
updateHeroShift();

document.querySelectorAll("[data-year]").forEach((node) => {
  node.textContent = String(new Date().getFullYear());
});
