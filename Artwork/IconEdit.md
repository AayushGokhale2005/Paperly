# Paperly icon artwork

Reference: `IconReference.png`, supplied by the user. Background removal uses the built-in image generation/editing tool, not an API in the app. The app contains no AI functionality.

Transparent master: `PaperlyMark.png`. Preserve its alpha when reusing the logo.

Installed app icon: `Paperly/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, a 1024×1024 opaque sRGB PNG on a deep navy backing (#061126). The user's white tile and surrounding background are removed; the pale underside of the folded paper belongs to the mark and is retained. The system supplies the icon's corner mask.

Regenerate the compiled asset from the transparent master:

```sh
swift Scripts/GenerateAppIcon.swift Artwork/PaperlyMark.png \
  Paperly/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Background extraction prompt

Use case: background-extraction. Edit the supplied image: remove ALL background, the white rounded-square tile and its exterior shadow, leaving ONLY the exact blue P-shaped folded-paper logo as a clean transparent cutout. Preserve the logo's exact silhouette, blue gradients, folded pale-blue/white underside, lighting and proportions; the pale folded underside is part of the logo and must remain. No redesign, no additional objects, no text. Center the isolated blue paper P on a square transparent canvas, enlarged to occupy approximately 76% of canvas height with balanced transparent padding. No white tile, no white background, no checkerboard baked into pixels. Actual alpha transparency.

## Alpha edge cleanup prompt

Use case: background-extraction. Clean the alpha matte of this isolated folded-paper P logo. Preserve the current blue gradients, exact silhouette, folded pale paper underside, size and placement. Remove the ragged cyan/blue fringe, colored speckles, edge glow and exterior shadows ALL AROUND the outside contour. Make the outer contour smooth, crisp and carefully antialiased with a narrow clean transition to fully transparent pixels. No redesign, no background, no tile, no added shadow, no checkerboard texture. The paper fold remains intact, including its pale white underside. Output a professional clean transparent PNG icon mark.
