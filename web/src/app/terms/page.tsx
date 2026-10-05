import type { Metadata } from "next";
import LegalPage from "@/components/LegalPage";
import { absolute, DEVELOPER, route } from "@/lib/config";

export const metadata: Metadata = {
  title: "Terms of Use",
  description: "The terms for using the Herald app and this website.",
  alternates: { canonical: "/terms" },
  openGraph: { title: "Herald terms of use", description: "The terms for using the Herald app and this website.", url: absolute("/terms"), type: "website", siteName: "Herald" },
};

export default function TermsPage() {
  return (
    <LegalPage title="Terms of Use" updated="October 5, 2026">
      <p>
        These terms cover the Herald app for macOS and this website, both provided by {DEVELOPER.name}, working as{" "}
        {DEVELOPER.studio}. By installing or using Herald you agree to them. If you do not agree, do not use the app.
      </p>

      <h2>The app</h2>
      <ul>
        <li><strong>Price.</strong> Herald is free to download and use.</li>
        <li><strong>Licence.</strong> You may install and use Herald on Macs you own or control, for personal or commercial work.</li>
        <li><strong>Beta software.</strong> Herald is under active development. Features can change, and a release can contain defects.</li>
      </ul>

      <h2>Your responsibilities</h2>
      <ul>
        <li><strong>Actions run with your permissions.</strong> Herald can run Shortcuts, scripts and shell commands that you add or allow. You are responsible for what they do. Allow an app to run code only if you trust it.</li>
        <li><strong>The relay is yours.</strong> If you deploy the optional relay, it runs in your own Cloudflare account under Cloudflare&rsquo;s terms. You are responsible for that account, its costs and who you connect to it.</li>
        <li><strong>Lawful use.</strong> Do not use Herald to break the law or to send notifications to a Mac you are not allowed to use.</li>
      </ul>

      <h2>Third-party services</h2>
      <p>
        Herald can work with services from other companies, such as Cloudflare, Apple Shortcuts, and AI agents you
        connect. Those services have their own terms, and the developer is not responsible for them.
      </p>

      <h2>No warranty</h2>
      <p>
        Herald is provided &ldquo;as is&rdquo;, without warranty of any kind, express or implied, including warranties
        of merchantability, fitness for a particular purpose and non-infringement. Do not rely on Herald as the only
        alert for anything where a missed notification could cause harm or loss.
      </p>

      <h2>Limitation of liability</h2>
      <p>
        To the extent the law allows, the developer is not liable for any indirect, incidental or consequential damages,
        or for lost data or lost profits, arising from the use of Herald or this website.
      </p>

      <h2>Privacy</h2>
      <p>The <a href={route("/privacy")}>Privacy Policy</a> describes what the app and this website do with data.</p>

      <h2>Changes</h2>
      <p>If these terms change, the new version is published on this page with a new date. Using Herald after a change means you accept the new terms.</p>

      <h2>Contact</h2>
      <p>
        Questions go to {DEVELOPER.name} through <a href={DEVELOPER.linkedin}>LinkedIn</a> or the contact options at{" "}
        <a href={DEVELOPER.contact}>services.mograph.life</a>.
      </p>
    </LegalPage>
  );
}
