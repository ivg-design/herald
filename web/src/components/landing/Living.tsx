import { QuietMock, StackMock, VoiceMock } from "./b-living-mocks";

export default function Living() {
  return (
    <section id="living" className="section section-paper on-paper">
      <div className="shell">
        <p className="eyebrow">Living with it</p>
        <h2 className="display max-w-[16ch] text-[clamp(40px,6vw,72px)]">Loud when it matters. Quiet when it doesn&rsquo;t.</h2>
        <div className="mt-12 grid grid-cols-[minmax(0,1fr)] gap-12 md:grid-cols-3 md:gap-8">
          <div className="min-w-0">
            <StackMock />
            <h3 className="m-0 mt-6 text-[19px] font-medium">Stacks with a counter</h3>
            <p className="mt-3 text-[15px] leading-relaxed text-paper-muted">Same sender again? The banner doesn&rsquo;t multiply, the count goes up. Click to fan the stack out, dismiss the whole group at once. Group by app, by issuer, or by sender.</p>
          </div>
          <div className="min-w-0">
            <QuietMock />
            <h3 className="m-0 mt-6 text-[19px] font-medium">Quiet hours</h3>
            <p className="mt-3 text-[15px] leading-relaxed text-paper-muted">Pick windows where voice and sound stay off and, if you want, banners wait. Per app overrides for the ones that may wake you.</p>
          </div>
          <div className="min-w-0">
            <VoiceMock />
            <h3 className="m-0 mt-6 text-[19px] font-medium">A voice, if you want one</h3>
            <p className="mt-3 text-[15px] leading-relaxed text-paper-muted">Attach a spoken message to any notification. Local neural TTS, nothing leaves the Mac, and the text is logged so you can read what you missed.</p>
          </div>
        </div>
      </div>
    </section>
  );
}
