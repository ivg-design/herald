import Link from "next/link";
import type { ComponentProps } from "react";
import { route } from "@/lib/config";

type Props = Omit<ComponentProps<typeof Link>, "href"> & { href: string };

/** Internal links honour the forge sub-path; external links open in a new tab. */
export default function SiteLink({ href, children, ...rest }: Props) {
  if (/^(https?:|mailto:)/.test(href)) {
    return (
      <a href={href} target="_blank" rel="noopener noreferrer" {...(rest as object)}>
        {children}
      </a>
    );
  }
  if (href.startsWith("#")) {
    return (
      <a href={href} {...(rest as object)}>
        {children}
      </a>
    );
  }
  return (
    <Link href={route(href)} {...rest}>
      {children}
    </Link>
  );
}
