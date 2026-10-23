# Paperly website

Public website for the free, MIT-licensed native Paperly app. Built with Vite, React, TypeScript, and Motion for React (Framer Motion).

## Run locally

Use Node.js 22.12+ and npm.

```sh
cd website
npm ci
npm run dev
```

Open the URL printed by Vite. Build with `npm run build`; inspect that build with `npm run preview`. Upload the contents of `dist/` to a static host when ready. Relative asset paths support deployment under a subdirectory. Keep `privacy.html` and `support.html` alongside `index.html`; no SPA rewrite is required.

## Content and assets

`src/App.tsx` contains the public pages, verified release links, and product gallery. `src/styles.css` contains responsive layout and the rounded glass navigation. Motion respects system reduced-motion settings; navigation also has a reduced-transparency fallback.

The original README screenshots come from `../docs/images/`, and the logo from `../Artwork/PaperlyMark.png`. `npm run sync-assets` refreshes their copies in `public/`. Shipped copies carry origin metadata; their pixels are unchanged. Reapply provenance metadata after refreshing assets if using the Impeccable asset workflow.

The release download is an unsigned IPA requiring signing. The Mac ZIP is development-signed, not notarized, and intended for registered test Macs. Other Mac users build and sign from source. Update these links when official distribution changes. There is no browser notes client or analytics integration in this website.

## Verification

The production build is checked with TypeScript and Vite. Browser checks cover desktop, phone and narrow preview layouts, menu keyboard dismissal, gallery keyboard navigation, and privacy/support pages. Product screenshots use rounded frames without changing their source pixels.
