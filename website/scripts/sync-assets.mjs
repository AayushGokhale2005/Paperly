import { copyFile, mkdir } from 'node:fs/promises'
const root = new URL('../', import.meta.url)
const screenshots = ['ipad-workspace.jpg', 'ipad-handwriting.jpg', 'iphone-rich-text.png', 'mac-rich-text.png', 'mac-audio-notes.png']
await mkdir(new URL('public/screenshots/', root), { recursive: true })
await mkdir(new URL('public/brand/', root), { recursive: true })
for (const file of screenshots) {
  await copyFile(new URL(`../docs/images/${file}`, root), new URL(`public/screenshots/${file}`, root))
}
await copyFile(new URL('../Artwork/PaperlyMark.png', root), new URL('public/brand/paperly.png', root))
console.log('Copied the original README screenshots and Paperly logo.')
