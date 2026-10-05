import type { Metadata } from "next";
import LegalPage from "@/components/LegalPage";
import { absolute, DEVELOPER } from "@/lib/config";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "What Herald and this website do with your data: the app keeps everything on your Mac and collects nothing.",
  alternates: { canonical: "/privacy" },
  openGraph: { title: "Herald privacy policy", description: "Herald keeps everything on your Mac and collects nothing.", url: absolute("/privacy"), type: "website", siteName: "Herald" },
};

export default function PrivacyPage() {
  return (
    <LegalPage title="Privacy Policy" updated="October 5, 2026">
      <p>
        Herald is made by {DEVELOPER.name}, working as {DEVELOPER.studio}. This page says what the Herald app and this
        website do with your data. The short version: the app collects nothing and sends nothing to the developer.
      </p>

      <h2>The app</h2>
      <p>Herald runs on your Mac and keeps its data there.</p>
      <ul>
        <li><strong>No account, no analytics, no telemetry.</strong> Herald does not report usage, crashes or anything else to the developer or to any third party.</li>
        <li><strong>Your notifications stay on your Mac.</strong> Notifications, history, templates, settings and replies are stored in your user Library folder. You can delete history in the app at any time, and removing the app&rsquo;s data folder removes everything.</li>
        <li><strong>Voice is local.</strong> Spoken notifications are generated on your Mac. Text is not sent to a speech service. Recorded replies are transcribed on your Mac.</li>
        <li><strong>The local API listens only on your Mac.</strong> It accepts connections from this computer and requires a token stored in your user folder.</li>
      </ul>

      <h2>When Herald connects to the network</h2>
      <p>Herald makes a network connection only for something you set up:</p>
      <ul>
        <li><strong>Actions you add.</strong> A button that opens a link, calls back the app that sent the notification, or runs a Shortcut, script or command does what you or that app configured.</li>
        <li><strong>The optional relay.</strong> If you turn on the cloud relay, Herald connects to a Cloudflare Worker that you deploy in your own Cloudflare account. Notifications sent through it pass through that Worker. The developer does not operate it and cannot see its traffic. Cloudflare&rsquo;s own privacy policy applies to your account there.</li>
        <li><strong>Agents and connectors you approve.</strong> A cloud agent you connect through the relay can send notifications and receive your replies. You can revoke a connection in Settings.</li>
        <li><strong>Animation assets.</strong> A Rive animation that references assets hosted by Rive loads them from Rive&rsquo;s servers when it plays.</li>
        <li><strong>Voice model download.</strong> If you install the voice, its model files are downloaded once from GitHub and its Python packages from the Python Package Index.</li>
      </ul>

      <h2>This website</h2>
      <ul>
        <li><strong>No cookies and no analytics scripts.</strong> The site sets no tracking cookies and loads no advertising or analytics code.</li>
        <li><strong>Hosting logs.</strong> The site is hosted on Vercel, which, like any web host, processes your IP address and browser details to deliver pages and keeps short-lived server logs.</li>
        <li><strong>Downloads.</strong> The installer is downloaded from GitHub, which processes the request under its own privacy policy.</li>
      </ul>

      <h2>Children</h2>
      <p>Herald is a general utility and is not directed at children. It collects no personal information from anyone.</p>

      <h2>Changes</h2>
      <p>If this policy changes, the new version is published on this page with a new date.</p>

      <h2>Contact</h2>
      <p>
        Questions about privacy go to {DEVELOPER.name} through <a href={DEVELOPER.linkedin}>LinkedIn</a> or the contact
        options at <a href={DEVELOPER.contact}>services.mograph.life</a>.
      </p>
    </LegalPage>
  );
}
