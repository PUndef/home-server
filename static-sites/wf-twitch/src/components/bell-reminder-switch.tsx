import { IconBell, IconBellOff } from "@tabler/icons-react";
import { cn } from "@/lib/utils";

type BellReminderSwitchProps = {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  disabled?: boolean;
  label?: string;
  compact?: boolean;
  id?: string;
};

function TrackSwitch({ checked, size = "md" }: { checked: boolean; size?: "sm" | "md" }) {
  const sm = size === "sm";

  return (
    <span
      aria-hidden
      className={cn(
        "inline-flex shrink-0 items-center rounded-full p-0.5 transition-colors",
        sm ? "h-5 w-9" : "h-6 w-11",
        checked ? "bg-purple-600" : "bg-muted-foreground/30",
      )}
    >
      <span
        className={cn(
          "block rounded-full bg-background shadow-sm transition-transform duration-200 ease-out",
          sm ? "size-4" : "size-5",
          checked && (sm ? "translate-x-4" : "translate-x-5"),
        )}
      />
    </span>
  );
}

export function BellReminderSwitch({
  checked,
  onCheckedChange,
  disabled,
  label = "Напоминания",
  compact,
  id,
}: BellReminderSwitchProps) {
  return (
    <button
      id={id}
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onCheckedChange(!checked)}
      className={cn(
        "inline-flex items-center rounded-lg border transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-purple-500/40 disabled:cursor-not-allowed disabled:opacity-50",
        compact ? "gap-2 px-2 py-1.5" : "gap-3 px-3 py-2",
        checked
          ? "border-purple-500/40 bg-purple-500/10 text-purple-100"
          : "border-border/80 bg-card/40 text-muted-foreground hover:bg-muted/40",
      )}
    >
      <span
        className={cn(
          "flex shrink-0 items-center justify-center rounded-md",
          compact ? "size-7" : "size-8",
          checked ? "text-purple-300" : "text-muted-foreground",
        )}
      >
        {checked ? (
          <IconBell className={compact ? "size-4" : "size-[1.125rem]"} stroke={2} />
        ) : (
          <IconBellOff className={cn(compact ? "size-4" : "size-[1.125rem]", "opacity-80")} stroke={2} />
        )}
      </span>

      {!compact && <span className="text-sm font-medium leading-none">{label}</span>}

      <TrackSwitch checked={checked} size={compact ? "sm" : "md"} />
    </button>
  );
}
