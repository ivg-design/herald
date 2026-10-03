import { QuietMock, StackMock, VoiceMock } from "./b-living-mocks";

export default function Living() {
  return (
    <section id="living" className="section night">
      <div className="shell g">
        <h2 className="display display-l col-span-full lg:col-span-8">Loud when it matters. Quiet when it doesn&rsquo;t.</h2>
        <div className="col-span-full mt-8 min-w-0 lg:col-span-5 lg:mt-12">
          <StackMock />
          <h3 className="display display-m m-0 mt-10">Stacks with a counter</h3>
          <p className="body mt-4">Same sender again? The banner doesn&rsquo;t multiply, the count goes up. Click to fan the stack out, dismiss the whole group at once. Group by app, by issuer, or by sender.</p>
        </div>
        <div className="col-span-full mt-8 flex min-w-0 flex-col gap-16 lg:col-span-7 lg:mt-12">
          <div>
            <QuietMock />
            <h3 className="display display-m m-0 mt-10">Quiet hours</h3>
            <p className="body mt-4">Pick windows where voice and sound stay off and, if you want, banners wait. Per app overrides for the ones that may wake you.</p>
          </div>
          <div>
            <VoiceMock />
            <h3 className="display display-m m-0 mt-10">A voice, if you want one</h3>
            <p className="body mt-4">Attach a spoken message to any notification. Local neural TTS, nothing leaves the Mac, and the text is logged so you can read what you missed.</p>
          </div>
        </div>
      </div>
    </section>
  );
}
