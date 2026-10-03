import SectionHead from "./SectionHead";
import { QuietMock, StackMock, VoiceMock } from "./b-living-mocks";

export default function Living() {
  return (
    <section id="living" className="section night">
      <div className="shell g">
        <SectionHead title={<>Loud when it matters. Quiet when it doesn&rsquo;t.</>} titleCols="lg:col-span-10" />
        <QuietMock />
        <div className="col-span-full min-w-0 lg:col-span-5 mt-12 lg:mt-14">
          <h3 className="display display-m m-0">Stacks with a counter</h3>
          <p className="body mt-4 max-w-[44ch]">Same sender again? The banner doesn&rsquo;t multiply, the count goes up. Click to fan the stack out, dismiss the whole group at once. Group by app, by issuer, or by sender.</p>
          <div className="mt-6"><StackMock /></div>
        </div>
        <div className="col-span-full min-w-0 lg:col-span-6 lg:col-start-7 mt-12 lg:mt-14">
          <h3 className="display display-m m-0">A voice, if you want one</h3>
          <p className="body mt-4 max-w-[44ch]">Attach a spoken message to any notification. Local neural TTS, nothing leaves the Mac, and the text is logged so you can read what you missed.</p>
          <div className="mt-6"><VoiceMock /></div>
        </div>
      </div>
    </section>
  );
}
