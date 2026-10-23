---
name: Paperly website
description: An open product desk for a free native notebook.
colors:
  ink: "#171c25"
  muted: "#5c6674"
  blue: "#1262ed"
  blue-deep: "#0849ba"
  wash: "#edf3ff"
  line: "#e2e6ed"
  white: "#ffffff"
  section: "#f4f7fc"
  secondary-border: "#c9d2df"
  secondary-hover: "#f5f7fa"
  glass-fallback: "#f8fbff"
typography:
  display:
    fontFamily: "Geist Variable, sans-serif"
    fontSize: "clamp(3.4rem, 5.65vw, 5.25rem)"
    fontWeight: 620
    lineHeight: 1.04
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Geist Variable, sans-serif"
    fontSize: "clamp(2.25rem, 3.6vw, 3.15rem)"
    fontWeight: 570
    lineHeight: 1.1
    letterSpacing: "-0.035em"
  title:
    fontFamily: "Geist Variable, sans-serif"
    fontSize: "1.65rem"
    fontWeight: 580
    lineHeight: 1.25
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Geist Variable, sans-serif"
    fontSize: "14px"
    lineHeight: 1.65
  label:
    fontFamily: "Geist Variable, sans-serif"
    fontSize: "14px"
    fontWeight: 580
rounded:
  control: "0px"
  navigation: "22px"
  navigation-mobile: "18px"
  screenshot: "16px"
  screenshot-mobile: "10px"
  phone-mobile: "8px"
spacing:
  section: "112px"
  section-tablet: "85px"
  section-mobile: "64px"
  gutter: "48px"
  gutter-tablet: "32px"
  gutter-mobile: "20px"
  gutter-narrow: "16px"
components:
  button-primary:
    backgroundColor: "{colors.blue}"
    textColor: "{colors.white}"
    rounded: "{rounded.control}"
    padding: "14px 20px"
    typography: "{typography.label}"
  button-primary-hover:
    backgroundColor: "{colors.blue-deep}"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "14px 20px"
    typography: "{typography.label}"
  button-secondary-hover:
    backgroundColor: "{colors.secondary-hover}"
  navigation:
    textColor: "{colors.ink}"
    rounded: "{rounded.navigation}"
    padding: "0 24px"
  gallery-panel:
    backgroundColor: "{colors.section}"
    rounded: "{rounded.control}"
  gallery-tab-selected:
    backgroundColor: "transparent"
    textColor: "{colors.blue}"
    rounded: "{rounded.control}"
    padding: "18px 9px 18px 0"
---

# Design System: Paperly website

## Overview

**Creative North Star: "The Open Product Desk"**

Paperly's public website is modern, spacious, and direct. White and cool pale-blue fields give the original native-app screenshots room to explain the product. Near-black Geist typography and electric-blue actions make the reading and install paths easy to follow.

This direction comes from the user's explicit requests and supplied product imagery. It is not an approved generated comp or an externally verified quality-bar reference. This document governs the Vite website only; the native app has its own design system.

**Key Characteristics:**
- Real README screenshots and the supplied Paperly logo.
- Large, closely tracked headings and concise supporting copy.
- Rectangular controls with selectively rounded navigation and screenshots.
- Quiet motion and readable preference-based fallbacks.

## Colors

The palette is clear white, cool pale blue, near-black text, and one decisive blue accent. Frontmatter values are normative.

### Primary
- **Electric Blue** (`blue`): primary actions, highlighted heading text, selected gallery tabs, links, and focus outlines.
- **Deep Action Blue** (`blue-deep`): primary-action hover state.

### Neutral
- **Ink** (`ink`): headings, primary copy, and neutral controls.
- **Slate** (`muted`): explanatory text and secondary navigation context.
- **White** (`white`): page ground and primary-action text.
- **Cool Wash** (`wash`): the hero screenshot stage.
- **Pale Section** (`section`): gallery and ownership surfaces.
- **Quiet Rule** (`line`): dividers that structure content without card boxes.
- **Secondary Border** (`secondary-border`) and **Secondary Hover** (`secondary-hover`): outlined-action states.
- **Opaque Glass** (`glass-fallback`): readable navigation when transparency is unavailable or reduced.

**The Action Blue Rule.** Reserve the accent for actionable or emphasized content; use neutral rules and pale fields for structure.

## Typography

**Display Font:** Geist Variable, with sans-serif fallback.
**Body Font:** Geist Variable, with sans-serif fallback.

The single variable family provides precise, compact headings and comfortable explanatory text. Display, headline, title, body, and label roles are recorded in frontmatter. Body size varies with context: gallery and FAQ copy is compact; hero and source introductions are larger. Use balanced wrapping for headings.

At tablet and mobile widths, display sizing changes to fit the composition. The small-screen heading uses a viewport-responsive clamp; below the narrowest breakpoint it reduces further. Document pages use a smaller display scale and longer body leading. Preserve these contextual roles rather than forcing every paragraph to one size.

## Layout

The content shell caps at (1240px), with side gutters from the frontmatter spacing scale. The shell moves to tablet gutters at (1100px), mobile gutters at (580px), and narrow gutters at (360px). Standard sections use the recorded section spacing scale. At (1600px) and above, the hero gains vertical breathing room.

Desktop layouts pair text and imagery in unequal columns. At (800px), hero, gallery, ownership, source, and FAQ content stack. Download options stack at (580px). The gallery tab rail scrolls horizontally on small screens. Privacy and support use a narrower reading column, with document body content capped at (700px).

## Elevation & Depth

Depth comes from pale tonal fields and diffuse screenshot shadows. Navigation is the explicit glass exception: a translucent gradient, fine white border, inset highlight, and blurred backdrop. Use the opaque fallback for reduced transparency or unsupported backdrop filtering. Shadow and glass values live in the sidecar because the frontmatter component schema cannot express them.

**The Product Depth Rule.** Give depth to the actual product imagery and navigation; keep prose sections open and separated by thin rules.

## Shapes

Controls, download actions, content fields, and tab rails are rectangular. Navigation and product screenshots are the user-requested exceptions, using the responsive radius tokens in frontmatter. The phone preview shares the desktop screenshot radius and uses its smaller dedicated mobile radius. Clip image wrappers so their corners remain consistent with the images.

**The Selective Rounding Rule.** Preserve the rounded glass navigation and screenshot frames without turning buttons, labels, or tabs into pills.

## Components

### Buttons

Primary actions are solid blue with white text; secondary actions use a thin neutral border. Both are square, compact, and pair concise text with a restrained line icon. Hover changes color or border rather than scale. Mobile actions reduce padding to (13px 18px) and minimum height to (47px). Keyboard focus is a blue outline (2px) offset by (5px).

### Navigation

The sticky glass navigation uses a wordmark and plain text links. Desktop links sit in a single row; at the mobile breakpoint, a square icon control opens a vertically arranged rounded glass panel. Preserve semantic navigation, visible focus, expanded state, and Escape-to-close behavior. The header fades in once over (0.3s).

### Product imagery and gallery

Use the supplied logo and original README screenshots, with concise descriptions. Do not substitute fabricated product UI or mock device frames. Hero screenshots reveal through opacity and a subtle (3px) vertical settle; the main reveal lasts (0.65s), with the phone preview at (0.55s). The gallery changes screenshots through a short opacity transition with a (3px) settle, while its blue underline travels between tabs. Keep tab roles, arrow-key navigation, Home/End behavior, and a focusable associated panel.

Motion for React owns these transitions. Reduced motion removes hero displacement, gallery fades, and underline travel; CSS animations, transitions, and smooth scrolling also yield to the preference. Avoid continuous decorative movement or repeated section reveals.

### Open containers and disclosure rows

The gallery is an open pale panel rather than a floating card. Ownership lists, install choices, and FAQs rely on rules and spacing. FAQs use native disclosure controls with a rotating plus icon. The website currently has no form inputs, chips, or card library to extend.

## Do's and Don'ts

### Do:
- **Do** use real README screenshots and concise image descriptions.
- **Do** preserve the responsive navigation and screenshot radius tokens.
- **Do** keep primary actions rectangular and blue.
- **Do** retain keyboard controls, visible focus, and motion/transparency fallbacks.

### Don't:
- **Don't** turn buttons, tabs, or platform labels into pills.
- **Don't** replace native screenshots with fabricated interfaces or mock device frames.
- **Don't** add continuous decorative motion or repeated section reveals.
- **Don't** promote the website's glass treatment into the native app's design system.

### Device showcase

User-requested device frames surround the unchanged screenshots. iPad uses a dark bezel and landscape camera. MacBook uses a dark lid, silver deck, keyboard and trackpad. Its CSS perspective is 3000px (1800px on phones). Motion scroll progress rotates the lid from -82° to 0° around the bottom hinge; reduced motion renders it open. The dedicated Mac section makes this interaction discoverable without choosing a gallery tab.

The hero hardware sits over a diffuse blue radial field, blurred 40px on desktop and 25px on phones. The device stage is transparent so no rectangular backdrop edge remains; only the backdrop is blurred.
