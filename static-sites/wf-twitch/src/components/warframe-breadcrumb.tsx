import { IconChevronRight, IconHome } from "@tabler/icons-react";
import { siteUrl } from "@shared/site-urls";

export function WarframeBreadcrumb({ current }: { current: string }) {
  return (
    <nav aria-label="Breadcrumb" className="mb-6 border-b border-border/60 pb-4">
      <ol className="flex flex-wrap items-center gap-1.5 text-sm">
        <li>
          <a
            className="inline-flex items-center gap-1.5 rounded-sm text-muted-foreground transition hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
            href={siteUrl("warframe")}
          >
            <IconHome className="size-4" />
            <span>Warframe</span>
          </a>
        </li>
        <li aria-hidden="true" className="text-muted-foreground/70">
          <IconChevronRight className="size-4" />
        </li>
        <li className="font-medium text-foreground">{current}</li>
      </ol>
    </nav>
  );
}
