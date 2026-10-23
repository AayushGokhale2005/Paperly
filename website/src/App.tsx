import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { AnimatePresence, motion, MotionConfig, useReducedMotion, useScroll, useTransform } from 'motion/react'
import { ArrowDown, ArrowDownToLine, ArrowRight, ArrowUpRight, FolderOpen, FileText, Github, Laptop, Menu, Mic, PenLine, Plus, Smartphone, Tablet, X } from 'lucide-react'

const REPO = 'https://github.com/AayushGokhale2005/Paperly'
const RELEASES = `${REPO}/releases`
const IPA = `${REPO}/releases/latest/download/Paperly-unsigned.ipa`
const MAC = `${REPO}/releases/latest/download/Paperly-Mac-development.zip`
const asset = (path: string) => `${import.meta.env.BASE_URL}${path}`
const image = (name: string) => asset(`screenshots/${name}`)
const page = window.location.pathname.endsWith('/privacy.html') ? 'privacy' : window.location.pathname.endsWith('/support.html') ? 'support' : 'home'

function Brand({ footer = false }: { footer?: boolean }) {
  return <a href="./" className={`brand${footer ? ' brand-footer' : ''}`} aria-label="Paperly home"><img src={asset('brand/paperly.png')} alt="" width="36" height="36" /><span>Paperly</span></a>
}

function Header() {
  const [open, setOpen] = useState(false)
  const toggle = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    const onKey = (event: globalThis.KeyboardEvent) => {
      if (event.key === 'Escape' && open) { setOpen(false); toggle.current?.focus() }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])
  return <motion.header className="site-header" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.3 }}>
    <div className="header-inner shell" data-menu-open={open}>
      <Brand />
      <nav className={`navigation${open ? ' navigation-open' : ''}`} id="navigation" aria-label="Main navigation">
        <a href="./#features" onClick={() => setOpen(false)}>The app</a>
        <a href="./#open-source" onClick={() => setOpen(false)}>Open source</a>
        <a href="./support.html" aria-current={page === 'support' ? 'page' : undefined} onClick={() => setOpen(false)}>Support</a>
        <a href={REPO} className="nav-github"><Github size={18} strokeWidth={1.7} aria-hidden="true" /> GitHub <ArrowUpRight size={14} aria-hidden="true" /></a>
      </nav>
      <button ref={toggle} type="button" className="menu-toggle" aria-label={open ? 'Close menu' : 'Open menu'} aria-expanded={open} aria-controls="navigation" onClick={() => setOpen(!open)}>{open ? <X /> : <Menu />}</button>
    </div>
  </motion.header>
}

const views = [
  { id: 'handwriting', label: 'Handwriting', icon: PenLine, title: 'Think outside the text box.', description: 'Draw a connection. Work out a problem. Write the way you think with native Apple Pencil tools.', detail: 'Blank, ruled, grid, and dot paper. Editable ink, always.', file: 'ipad-handwriting.jpg', alt: 'Handwritten notes on iPad', platform: 'iPad' },
  { id: 'text', label: 'Text', icon: FileText, title: 'Give your ideas a little structure.', description: 'Go from a passing thought to a clear plan with headings, lists, checkboxes, and quotes.', detail: 'A focused editor on iPhone, iPad, and Mac.', file: 'mac-rich-text.png', alt: 'Text document on Mac', platform: 'Mac' },
  { id: 'workspace', label: 'Workspace', icon: FolderOpen, title: 'Everything has a place.', description: 'Keep notebooks, text documents, and PDFs together. Organize with folders, then find your way back with search.', detail: 'Your folders follow you across devices with optional Google Drive sync.', file: 'ipad-workspace.jpg', alt: 'Paperly workspace on iPad', platform: 'iPad' },
  { id: 'audio', label: 'Audio notes', icon: Mic, title: 'Be in the conversation.', description: 'Save a recording, transcribe it with local Whisper, and turn the transcript into editable notes.', detail: 'First-time model download required. Generated notes need compatible Apple Intelligence hardware.', file: 'mac-audio-notes.png', alt: 'Audio notes on Mac', platform: 'Mac' },
]

function MacBook({ file, alt }: { file: string; alt: string }) {
  const frame = useRef<HTMLDivElement>(null)
  const reduced = useReducedMotion()
  const { scrollYProgress } = useScroll({ target: frame, offset: ['start 0.95', 'start 0.28'] })
  const opening = useTransform(scrollYProgress, [0, 0.85], [-82, 0])
  return <div ref={frame} className="macbook-scene">
    <div className="macbook-deck" aria-hidden="true"><span /></div>
    <motion.div className="device-macbook macbook-lid" style={{ rotateX: reduced ? 0 : opening }}>
      <img src={image(file)} alt={alt} width="1024" height="645" loading="lazy" />
    </motion.div>
  </div>
}

function ProductGallery() {
  const [active, setActive] = useState(0)
  const refs = useRef<(HTMLButtonElement | null)[]>([])
  const current = views[active]
  const reduced = useReducedMotion()
  function move(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let next = index
    if (event.key === 'ArrowRight') next = (index + 1) % views.length
    else if (event.key === 'ArrowLeft') next = (index - 1 + views.length) % views.length
    else if (event.key === 'Home') next = 0
    else if (event.key === 'End') next = views.length - 1
    else return
    event.preventDefault(); setActive(next); refs.current[next]?.focus()
  }
  return <section className="features section-space shell" id="features" aria-labelledby="features-title">
    <div className="section-intro"><h2 id="features-title">A place for every<br />{' '}kind of thought.</h2><p>Some ideas need a keyboard.<br />{' '}Others need a blank page.</p></div>
    <div className="gallery-tabs" role="tablist" aria-label="Explore Paperly">
      {views.map((view, index) => <button type="button" id={`tab-${view.id}`} key={view.id} ref={element => { refs.current[index] = element }} role="tab" aria-selected={index === active} aria-controls="product-panel" tabIndex={index === active ? 0 : -1} onClick={() => setActive(index)} onKeyDown={event => move(event, index)}><view.icon size={18} strokeWidth={1.7} aria-hidden="true" />{view.label}{index === active && <motion.span className="tab-indicator" layoutId="gallery-indicator" transition={{ duration: reduced ? 0 : 0.22, ease: "easeOut" }} />}</button>)}
    </div>
    <div id="product-panel" className="gallery-panel" role="tabpanel" aria-labelledby={`tab-${current.id}`} tabIndex={0}>
      <div className="gallery-image-wrap"><AnimatePresence mode="wait" initial={false}><motion.div className={`gallery-device ${current.platform === 'Mac' ? '' : 'device-shot device-ipad'}`} initial={{ opacity: 0, y: reduced ? 0 : 3 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: reduced ? 0 : 0.14 }} key={current.file}>{current.platform === 'Mac' ? <MacBook file={current.file} alt={current.alt} /> : <img src={image(current.file)} alt={current.alt} width="1024" height="768" loading="lazy" className="gallery-image" />}</motion.div></AnimatePresence></div>
      <div className="gallery-copy"><h3>{current.title}</h3><p>{current.description}</p><p className="gallery-detail">{current.detail}</p><a className="text-link" href={image(current.file)} target="_blank" rel="noreferrer">View screenshot <ArrowUpRight size={17} aria-hidden="true" /></a></div>
    </div>
    <div className="pdf-note"><FileText size={21} strokeWidth={1.6} aria-hidden="true" /><p>Reading something good? <strong>Import a PDF and make it your own.</strong> Keep the original underneath your editable annotations.</p></div>
  </section>
}

const questions = [
  ['Is Paperly really free?', 'Yes. Paperly is free to use and its source is available under the MIT license. There is no Paperly subscription.'],
  ['How do I install it?', 'Download the unsigned IPA from GitHub and sign it with your own Apple ID or provisioning profile, or build from source with Xcode. The Mac development download is for registered test Macs; other Macs can build and sign from source.'],
  ['Does it work offline?', 'Yes. Your notes save on your device. Google Drive sync is optional. Whisper needs an initial model download; transcription then runs locally.'],
  ['What do I need for audio notes?', 'Local transcription uses WhisperKit on supported devices. Generating structured notes also needs compatible Apple Intelligence hardware, supported software, and the on-device model enabled and ready.'],
  ['Can I take my notes elsewhere?', 'Export editable .paperly files for backup. Text documents also export as Markdown, and handwritten notebooks and PDFs can export as annotated PDF.'],
]

function FAQ({ full = false }: { full?: boolean }) {
  return <div className="faq-list">{questions.slice(0, full ? questions.length : 4).map(([question, answer]) => <details key={question}><summary>{question}<Plus size={21} strokeWidth={1.5} aria-hidden="true" /></summary><p>{answer}</p></details>)}</div>
}

function GetPaperly() {
  return <section className="get-section shell section-space" id="get-paperly" aria-labelledby="get-title">
    <div className="section-intro"><h2 id="get-title">Make a little room<br />{' '}for your next idea.</h2><p>Free to use.<br />{' '}Ready to make your own.</p></div>
    <div className="download-options">
      <article><div className="download-heading"><span><Smartphone size={25} strokeWidth={1.5} /><Tablet size={28} strokeWidth={1.5} /></span><h3>iPhone & iPad</h3></div><p>Download the latest build from GitHub.</p><a className="button button-primary" href={IPA}>Download IPA <ArrowDownToLine size={18} aria-hidden="true" /></a><p className="install-note">Unsigned build. Requires signing before installation.</p><a className="text-link" href="./support.html#installation">Installation guide <ArrowRight size={16} aria-hidden="true" /></a></article>
      <article><div className="download-heading"><Laptop size={31} strokeWidth={1.5} /><h3>Mac</h3></div><p>Try the native Mac Catalyst development build.</p><a className="button button-secondary" href={MAC}>Download for Mac <ArrowDownToLine size={18} aria-hidden="true" /></a><p className="install-note">Development-signed. Not notarized. For registered test Macs.</p><a className="text-link" href="./support.html#mac-installation">Mac installation guide <ArrowRight size={16} aria-hidden="true" /></a></article>
    </div>
  </section>
}

function Home() {
  const reduced = useReducedMotion()
  return <>
    <section className="hero shell" aria-labelledby="hero-title">
      <div className="hero-copy"><h1 id="hero-title">Your thoughts deserve<br />{' '}<span>a free page.</span></h1><p>A free, open-source home for your notes, sketches, PDFs, and recordings. Built for iPhone, iPad, and Mac.</p><div className="hero-actions"><a href="#get-paperly" className="button button-primary">Get Paperly <ArrowDown size={18} aria-hidden="true" /></a><a href={REPO} className="hero-source">View on GitHub <ArrowUpRight size={17} aria-hidden="true" /></a></div><div className="hero-platforms"><span><Smartphone size={16} aria-hidden="true" />iPhone</span><span><Tablet size={17} aria-hidden="true" />iPad</span><span><Laptop size={18} aria-hidden="true" />Mac</span></div></div>
      <div className="hero-stage"><motion.div className="hero-screenshot device-shot device-ipad" initial={{ opacity: reduced ? 1 : 0, y: reduced ? 0 : 3 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.65, delay: 0.1, ease: "easeOut" }}><img src={image('ipad-handwriting.jpg')} alt="Handwritten notes on iPad" width="1024" height="768" fetchPriority="high" /></motion.div><motion.div className="phone-peek" initial={{ opacity: reduced ? 1 : 0, y: reduced ? 0 : 3 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.55, delay: 0.3 }}><img src={image('iphone-rich-text.png')} alt="Text notes on iPhone" width="478" height="1024" /></motion.div></div>
    </section>
    <ProductGallery />
    <section className="mac-showcase shell" aria-labelledby="mac-title">
      <div className="section-intro"><h2 id="mac-title">A bigger space<br />{' '}for your ideas.</h2><p>The same workspace.<br />{' '}A native Mac app.</p></div>
      <MacBook file="mac-rich-text.png" alt="Paperly on MacBook" />
    </section>
    <section className="ownership-section" id="why-paperly" aria-labelledby="ownership-title"><div className="ownership-inner shell"><div><h2 id="ownership-title">The space is yours.<br />{' '}So are the notes.</h2><p>Write first. Connect only if you want to.<br />{' '}Paperly keeps the everyday things simple.</p></div><div className="ownership-list"><article><h3>Local comes first.</h3><p>Your notes live on your device. Writing doesn’t wait for a server or a connection.</p></article><article><h3>Private stays private.</h3><p>No ads or analytics. Handwriting recognition, transcription, and note generation run on-device.</p></article><article><h3>Sync on your terms.</h3><p>Connect Google Drive when you want your workspace on another device. Keep editing offline whenever you don’t.</p></article></div></div></section>
    <section className="open-source-section shell section-space" id="open-source" aria-labelledby="source-title"><div className="source-heading"><Github size={37} strokeWidth={1.4} aria-hidden="true" /><h2 id="source-title">Good ideas<br />{' '}belong to everyone.</h2></div><div className="source-copy"><p>Paperly is free and open source.<br />{' '}Read the code. Make it better. Make it yours.</p><div className="source-links"><a className="text-link" href={REPO}>Explore the repository <ArrowUpRight size={18} aria-hidden="true" /></a><a className="text-link" href={`${REPO}/blob/main/LICENSE`}>MIT license <ArrowUpRight size={18} aria-hidden="true" /></a><a className="text-link" href={`${REPO}#contributing`}>Contribute <ArrowUpRight size={18} aria-hidden="true" /></a></div></div></section>
    <section className="faq-section shell section-space" aria-labelledby="faq-title"><div><h2 id="faq-title">A few good<br />{' '}questions.</h2><a className="text-link" href="./support.html">More help <ArrowRight size={17} aria-hidden="true" /></a></div><FAQ /></section>
    <GetPaperly />
  </>
}

function Privacy() {
  return <article className="document-page shell" id="privacy-policy"><a href="./" className="text-link back-link">← Back to Paperly</a><h1>Your notes.<br />{' '}Your privacy.</h1><p className="document-lead">Paperly saves locally first. Here’s what stays on your device, and what happens when you choose to connect a service.</p><div className="document-body">
    <section><h2>What Paperly stores</h2><p>The app handles the content you create or import: text, handwriting, PDFs, images, recordings, transcripts, folders, and document metadata. These files are stored in Paperly’s local app storage.</p></section>
    <section><h2>Processing on your device</h2><p>Handwriting search uses Apple Vision. Audio transcription uses a local Whisper model, downloaded when needed. Supported note generation uses Apple’s on-device Foundation Models. Paperly does not operate a cloud AI service or upload your recordings for transcription.</p></section>
    <section><h2>Optional Google Drive sync</h2><p>Connecting Google Drive is your choice. When connected, Paperly uses Google Sign-In and the Drive API to exchange your workspace files with your Google account. Google processes that data under its own terms and privacy policy. Disconnecting stops future sync; it does not remove existing local or Drive copies.</p></section>
    <section><h2>Permissions</h2><p>The microphone is used when you choose to record. Photos and files are accessed when you choose content to import. Network access supports model downloads and Google services you connect. You can manage permissions in your device settings.</p></section>
    <section><h2>Analytics and advertising</h2><p>Paperly does not include third-party advertising or product analytics. This website does not use analytics scripts or advertising cookies. It serves its fonts and images locally. Your hosting provider may maintain ordinary server logs.</p></section>
    <section><h2>Keeping and deleting content</h2><p>Your content stays in app storage until you remove it or the app’s data. Items moved to Paperly’s Trash remain recoverable. Export a backup before removing the app. Copies in Google Drive must be managed separately through your Google account.</p></section>
    <section><h2>Questions</h2><p>Paperly’s source is available for inspection. For questions about the app’s data handling, <a href={`${REPO}/issues`}>open an issue on GitHub</a>. Issues are public, so please leave private notebook content out of your report.</p></section>
  </div></article>
}

function Support() {
  return <article className="document-page shell"><a href="./" className="text-link back-link">← Back to Paperly</a><h1>A little help<br />{' '}getting started.</h1><p className="document-lead">Paperly is an independent, open-source project. Find an install path below, or bring a question to GitHub.</p><div className="document-body">
    <section id="installation"><h2>Install on iPhone or iPad</h2><ol><li><a href={IPA}>Download the latest unsigned IPA</a> from GitHub.</li><li>Re-sign it with your own Apple ID, development certificate, or provisioning profile using a compatible sideloading tool, or build from source with Xcode.</li><li>Enable Developer Mode on the device and follow the tool’s installation instructions.</li></ol><p>The IPA cannot be installed directly without signing. For the full development setup, see the <a href={`${REPO}#getting-started`}>project README</a>.</p></section>
    <section id="mac-installation"><h2>Run on Mac</h2><p><a href={MAC}>Download the Mac development build</a> and unzip it. This app is signed with an Apple Development certificate for registered test Macs. It is not notarized and is not a public distribution installer. The current profile expires October 30, 2026 at 03:50 UTC (October 29 at 11:50 PM Eastern).</p><p>If your Mac is not included in the development profile, clone the repository, open Paperly in Xcode, select your own signing team, and build for the Mac Catalyst destination.</p><a className="text-link" href={`${REPO}#mac`}>Mac setup instructions <ArrowUpRight size={17} aria-hidden="true" /></a></section>
    <section id="compatibility"><h2>Compatibility</h2><dl className="compatibility"><div><dt>iPhone & iPad</dt><dd>iOS / iPadOS 17 or later</dd></div><div><dt>Mac</dt><dd>Development download for registered test Macs, or build from source</dd></div><div><dt>Handwriting</dt><dd>Apple Pencil or finger input</dd></div><div><dt>Audio transcription</dt><dd>Whisper model download; supported hardware</dd></div><div><dt>Generated notes</dt><dd>Compatible Apple Intelligence hardware and software; model enabled and ready</dd></div><div><dt>Google Drive</dt><dd>Optional; custom OAuth configuration for source builds</dd></div></dl></section>
    <section><h2>Common questions</h2><FAQ full /></section>
    <section><h2>Something not quite right?</h2><p>Include your device model, operating system version, and steps to reproduce the problem. Please don’t post private notes or recordings.</p><a className="button button-primary" href={`${REPO}/issues`}>Open a GitHub issue <ArrowUpRight size={18} aria-hidden="true" /></a></section>
  </div></article>
}

function Footer() {
  return <footer className="footer shell"><div className="footer-top"><Brand footer /><p>A little space for your thoughts.</p><a href={REPO} className="text-link">Built in the open <ArrowUpRight size={17} aria-hidden="true" /></a></div><div className="footer-bottom"><span>© {new Date().getFullYear()} Paperly contributors</span><nav aria-label="Footer navigation"><a href="./privacy.html">Privacy</a><a href="./support.html">Support</a><a href={`${REPO}/blob/main/LICENSE`}>MIT license</a><a href={RELEASES}>Releases</a></nav></div></footer>
}

export default function App() {
  return <MotionConfig reducedMotion="user"><a className="skip-link" href="#main">Skip to content</a><Header /><main id="main">{page === 'privacy' ? <Privacy /> : page === 'support' ? <Support /> : <Home />}</main><Footer /></MotionConfig>
}
