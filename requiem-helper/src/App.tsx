import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  ALL_REQUIEMS,
  REQUIEMS,
  type Attempt,
  type AttemptResult,
  type HelperState,
  type Requiem,
  type SlotMod,
  analyzeAttempts,
  createAttempt,
  defaultState,
  recommend,
} from "@/lib/requiem";
import { cn } from "@/lib/utils";

const STORAGE_KEY = "requiem-helper-state-v2";
const attemptResults: Array<{ value: AttemptResult; label: string }> = [
  { value: "unknown", label: "не проверялся" },
  { value: "correct", label: "верный / белый" },
  { value: "wrong", label: "неверный / красный" },
];

type ConfirmAction = {
  confirmLabel: string;
  description: string;
  onConfirm: () => void;
  title: string;
};

function loadState(): HelperState {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (!saved) return defaultState;
    const parsed = JSON.parse(saved) as Partial<HelperState>;
    return { ...defaultState, ...parsed, trialMods: parsed.trialMods ?? defaultState.trialMods };
  } catch {
    return defaultState;
  }
}

function stepStatus(index: number, activeIndex: number) {
  if (index < activeIndex) return "done";
  if (index === activeIndex) return "active";
  return "locked";
}

function statusLabel(status: ReturnType<typeof stepStatus>) {
  if (status === "done") return "готово";
  if (status === "active") return "сейчас";
  return "дальше";
}

function sequenceSlotHint(mod: string, known: Requiem[], originalMod = mod) {
  if (known.includes(mod as Requiem)) return "открытый murmur Requiem";
  if (mod === "Oull") return "Oull вместо неизвестного";
  if (originalMod === "любой" && mod !== "любой") return "сохранённый рандом для попытки";
  if (mod === "любой") return "выбери конкретный рандом ниже";
  return "пока не проверяем";
}

function resultLabel(result: AttemptResult) {
  return attemptResults.find((item) => item.value === result)?.label ?? result;
}

function hasRequiemIcon(mod: string): mod is Exclude<SlotMod, ""> {
  return (ALL_REQUIEMS as readonly string[]).includes(mod);
}

function RequiemIcon({ className, mod }: { className?: string; mod: string }) {
  if (!hasRequiemIcon(mod)) return null;

  return (
    <img
      alt={`${mod} Requiem`}
      className={cn("size-7 rounded-sm object-contain invert", className)}
      draggable={false}
      loading="lazy"
      src={`/requiems/${mod}.webp`}
    />
  );
}

function RoadmapStep({
  children,
  index,
  status,
  text,
  title,
}: {
  children?: ReactNode;
  index: number;
  status: ReturnType<typeof stepStatus>;
  text: string;
  title: string;
}) {
  return (
    <li className="relative pl-11">
      <div
        className={cn(
          "absolute left-0 top-4 z-10 flex size-7 items-center justify-center rounded-full border bg-background text-xs font-medium",
          status === "done" && "border-primary bg-primary text-primary-foreground",
          status === "active" && "border-primary text-primary ring-4 ring-primary/15",
          status === "locked" && "border-border text-muted-foreground",
        )}
      >
        {index + 1}
      </div>
      <Card
        className={cn(
          "transition",
          status === "active" && "ring-1 ring-primary/40",
          status === "locked" && "opacity-70",
        )}
      >
        <CardHeader className="gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={status === "active" ? "default" : "outline"}>{statusLabel(status)}</Badge>
            {status === "active" && <Badge variant="secondary">текущий шаг</Badge>}
          </div>
          <CardTitle className="text-lg">{title}</CardTitle>
          <CardDescription>{text}</CardDescription>
        </CardHeader>
        {children ? <CardContent>{children}</CardContent> : null}
      </Card>
    </li>
  );
}

function App() {
  const [state, setState] = useState<HelperState>(() => loadState());
  const [confirmAction, setConfirmAction] = useState<ConfirmAction | null>(null);
  const [draftAttempt, setDraftAttempt] = useState<Attempt | null>(null);
  const recommendation = useMemo(() => recommend(state), [state]);
  const analysis = useMemo(() => analyzeAttempts(state.attempts), [state.attempts]);
  const solvedAttempt = useMemo(
    () => state.attempts.find((attempt) => attempt.results.every((result) => result === "correct")) ?? null,
    [state.attempts],
  );
  const isSolved = Boolean(solvedAttempt) || analysis.fixed.every(Boolean);
  const resolvedAttemptMods = useMemo(
    () =>
      (solvedAttempt?.mods ?? recommendation.sequence).map((mod, index) => {
        if (mod === "любой") return state.trialMods[index] || "";
        if ((ALL_REQUIEMS as readonly string[]).includes(mod)) return mod as SlotMod;
        return "";
      }) as Attempt["mods"],
    [recommendation.sequence, solvedAttempt, state.trialMods],
  );
  const canStartAttempt = !isSolved && resolvedAttemptMods.every(Boolean);
  const canCommitDraft = draftAttempt
    ? draftAttempt.mods.every(Boolean) && draftAttempt.results.some((result) => result !== "unknown")
    : false;

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }, [state]);

  function setKnownAt(index: number, mod: Requiem) {
    setDraftAttempt(null);
    setState((current) => {
      const previous = current.known.slice(0, index);
      if (previous.includes(mod)) return current;
      const known = [...previous, mod];
      const trialMods = current.trialMods.map((trialMod) =>
        trialMod && known.includes(trialMod as Requiem) ? "" : trialMod,
      ) as HelperState["trialMods"];

      return { ...current, known, trialMods };
    });
  }

  function setTrialMod(slot: number, mod: Requiem) {
    setState((current) => {
      if (current.known.includes(mod)) return current;

      const trialMods = [...current.trialMods] as HelperState["trialMods"];
      trialMods[slot] = mod;

      return { ...current, trialMods };
    });
  }

  function updateDraftAttempt(slot: number, field: "mod" | "result", value: SlotMod | AttemptResult) {
    setDraftAttempt((current) => {
      if (!current) return current;

      const nextAttempt: Attempt = {
        ...current,
        mods: [...current.mods] as Attempt["mods"],
        results: [...current.results] as Attempt["results"],
      };

      if (field === "mod") {
        nextAttempt.mods[slot] = value as SlotMod;
      } else {
        nextAttempt.results[slot] = value as AttemptResult;
      }

      return nextAttempt;
    });
  }

  function startDraftAttempt() {
    if (isSolved) return;
    setDraftAttempt(createAttempt(resolvedAttemptMods));
  }

  function commitDraftAttempt() {
    if (isSolved || !draftAttempt || !canCommitDraft) return;

    setState((current) => ({
      ...current,
      attempts: [...current.attempts, draftAttempt],
    }));
    setDraftAttempt(null);
  }

  function resetAll() {
    setConfirmAction({
      title: "Reset all progress?",
      description: "Будут очищены открытые Requiem, filler-моды, черновик и вся история попыток.",
      confirmLabel: "Reset all",
      onConfirm: () => {
        setDraftAttempt(null);
        setState((current) => ({ ...current, known: [], trialMods: ["", "", ""], attempts: [] }));
      },
    });
  }

  function removeAttempt(id: string) {
    setConfirmAction({
      title: "Удалить попытку?",
      description: "Эта запись перестанет учитываться в расчёте следующего порядка.",
      confirmLabel: "Delete",
      onConfirm: () =>
        setState((current) => ({
          ...current,
          attempts: current.attempts.filter((attempt) => attempt.id !== id),
        })),
    });
  }

  function trialOptionsFor(slot: number) {
    return REQUIEMS.filter((mod) => {
      if (state.known.includes(mod)) return false;
      return (
        state.trialMods[slot] === mod ||
        !state.trialMods.some((trialMod, index) => index !== slot && trialMod === mod)
      );
    });
  }

  function revealPicker(revealIndex: number) {
    const selected = state.known[revealIndex] ?? "";
    const label = `${revealIndex + 1}-е открытое слово`;

    return (
      <div className="space-y-4">
        <div>
          <p className="mb-2 text-sm font-medium text-muted-foreground">
            Выбирай только то слово, которое реально открылось шкалой murmur. Рандомный мод для попытки здесь не
            отмечается.
          </p>
          <fieldset className="rounded-md border bg-input/20 p-3">
            <legend className="px-1 text-sm font-medium">
              {label}
              {!selected && <span className="ml-2 text-muted-foreground">выбери новое</span>}
            </legend>
            <div className="mt-2 grid gap-2 sm:grid-cols-2 md:grid-cols-4">
              {REQUIEMS.map((mod) => {
                const isUsedEarlier = state.known.slice(0, revealIndex).includes(mod);

                return (
                  <label
                    className={cn(
                      "flex cursor-pointer items-center gap-2 rounded-md border bg-background px-3 py-2 text-sm transition hover:bg-muted",
                      selected === mod && "border-primary bg-primary/10 text-primary",
                      isUsedEarlier && "cursor-not-allowed opacity-40",
                    )}
                    key={mod}
                  >
                    <input
                      checked={selected === mod}
                      className="size-3.5 accent-primary"
                      disabled={isUsedEarlier}
                      name={`known-${revealIndex}`}
                      onChange={() => setKnownAt(revealIndex, mod)}
                      type="radio"
                    />
                    <RequiemIcon className="size-7" mod={mod} />
                    <span>{mod}</span>
                  </label>
                );
              })}
            </div>
          </fieldset>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <label
            className={cn(
              "flex cursor-pointer items-center gap-2 rounded-md border bg-input/20 px-3 py-2 text-sm transition hover:bg-muted",
              state.hasOull && "border-primary bg-primary/10 text-primary",
            )}
          >
            <input
              checked={state.hasOull}
              className="size-3.5 accent-primary"
              onChange={(event) => setState((current) => ({ ...current, hasOull: event.target.checked }))}
              type="checkbox"
            />
            <RequiemIcon className="size-7" mod="Oull" />
            <span>Есть Oull</span>
          </label>
        </div>
      </div>
    );
  }

  const sequencePanel = (
    <div className="space-y-4">
      <div className="grid gap-2 sm:grid-cols-3">
        {recommendation.sequence.map((mod, index) => {
          const displayedMod = mod === "любой" ? state.trialMods[index] || "любой" : mod;
          const isTrialSlot = mod === "любой";

          return (
            <div
              className={cn(
                "rounded-md border bg-input/20 p-3",
                isTrialSlot && !state.trialMods[index] && "border-dashed border-primary/40",
              )}
              key={`${mod}-${index}`}
            >
              <p className="text-center text-sm text-muted-foreground">Слот {index + 1}</p>
              <div className="mt-3 flex flex-col items-center gap-2 text-center">
                <RequiemIcon className="size-16" mod={displayedMod} />
                <p className="text-lg font-semibold text-primary">{displayedMod}</p>
              </div>
              <p className="mt-1 text-center text-xs text-muted-foreground">
                {sequenceSlotHint(displayedMod, state.known, mod)}
              </p>

              {isTrialSlot && (
                <fieldset className="mt-3">
                  <legend className="mb-2 text-xs font-medium text-muted-foreground">
                    Выбери мод, который реально поставишь сюда
                  </legend>
                  <div className="grid grid-cols-2 gap-1">
                    {trialOptionsFor(index).map((trialMod) => (
                      <label
                        className={cn(
                          "flex cursor-pointer items-center gap-1.5 rounded border bg-background px-2 py-1 text-xs transition hover:bg-muted",
                          state.trialMods[index] === trialMod && "border-primary bg-primary/10 text-primary",
                        )}
                        key={trialMod}
                      >
                        <input
                          checked={state.trialMods[index] === trialMod}
                          className="size-3 accent-primary"
                          name={`trial-${index}`}
                          onChange={() => setTrialMod(index, trialMod)}
                          type="radio"
                        />
                        <RequiemIcon className="size-6" mod={trialMod} />
                        <span>{trialMod}</span>
                      </label>
                    ))}
                  </div>
                </fieldset>
              )}
            </div>
          );
        })}
      </div>
      <p className="text-sm text-muted-foreground">
        Если первый слот станет красным, игра дальше слоты не проверяет. В журнале ниже оставь остальные слоты как
        “не проверялся”.
      </p>
    </div>
  );

  const attemptWorkspace = (
    <div className="space-y-4">
      {isSolved ? (
        <div className="rounded-md border border-emerald-300/70 bg-emerald-300/10 p-4 text-sm">
          <p className="font-medium text-emerald-200">Sequence solved</p>
          <p className="mt-1 text-muted-foreground">
            Все три слота уже приняты игрой. Если один из них закрыт через Oull, третий murmur добивать не нужно.
          </p>
        </div>
      ) : !draftAttempt ? (
        <div className="rounded-md border border-dashed p-4">
          <p className="text-sm text-muted-foreground">
            Когда готов сделать Mercy, создай черновик. Он заполнится текущим Parazon-порядком и не попадёт в расчёт,
            пока ты не нажмёшь “Зафиксировать результат”.
          </p>
          <Button className="mt-3" disabled={!canStartAttempt} onClick={startDraftAttempt} type="button">
            Start attempt
          </Button>
        </div>
      ) : (
        <div className="rounded-md border border-primary/30 bg-primary/5 p-3">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div>
              <Badge>Черновик попытки</Badge>
              <p className="mt-1 text-sm text-muted-foreground">
                Отметь только слоты, которые игра реально проверила. После фиксации запись станет readonly.
              </p>
            </div>
            <Button onClick={() => setDraftAttempt(null)} size="sm" type="button" variant="outline">
              Cancel
            </Button>
          </div>

          <div className="grid gap-3 md:grid-cols-3">
            {[0, 1, 2].map((slot) => (
              <div className="rounded-md border bg-background p-3" key={slot}>
                <div className="mb-2 flex flex-col items-center gap-1 text-center">
                  <span className="text-sm text-muted-foreground">Слот {slot + 1}</span>
                  <RequiemIcon className="size-12" mod={draftAttempt.mods[slot]} />
                  <span className="text-base font-medium text-primary">{draftAttempt.mods[slot] || "Пусто"}</span>
                </div>
                <select
                  className="mb-2 h-9 w-full rounded-md border bg-background px-2 text-sm"
                  onChange={(event) => updateDraftAttempt(slot, "mod", event.target.value as SlotMod)}
                  value={draftAttempt.mods[slot]}
                >
                  <option value="">Пусто</option>
                  {ALL_REQUIEMS.map((mod) => (
                    <option key={mod} value={mod}>
                      {mod}
                    </option>
                  ))}
                </select>
                <select
                  className="h-9 w-full rounded-md border bg-background px-2 text-sm"
                  onChange={(event) => updateDraftAttempt(slot, "result", event.target.value as AttemptResult)}
                  value={draftAttempt.results[slot]}
                >
                  {attemptResults.map((result) => (
                    <option key={result.value} value={result.value}>
                      {result.label}
                    </option>
                  ))}
                </select>
              </div>
            ))}
          </div>

          <div className="mt-3 flex flex-wrap items-center gap-2">
            <Button disabled={!canCommitDraft} onClick={commitDraftAttempt} type="button">
              Lock result
            </Button>
            {!canCommitDraft && (
              <span className="text-sm text-muted-foreground">
                Нужно выбрать моды и отметить хотя бы один белый/красный результат.
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  );

  const attemptHistory = state.attempts.length ? (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-base font-medium">Зафиксированные попытки</h3>
        <Badge variant="outline">{state.attempts.length}</Badge>
      </div>
      {state.attempts.map((attempt, attemptIndex) => (
        <div className="rounded-md border bg-input/20 p-3" key={attempt.id}>
          <div className="mb-2 flex items-center justify-between gap-2">
            <Badge variant="secondary">Попытка {attemptIndex + 1}</Badge>
            <Button onClick={() => removeAttempt(attempt.id)} size="sm" type="button" variant="ghost">
              <span className="text-destructive">Delete</span>
            </Button>
          </div>
          <div className="grid gap-2 sm:grid-cols-3">
            {[0, 1, 2].map((slot) => {
              const result = attempt.results[slot];

              return (
                <div
                  className={cn(
                    "rounded-md border bg-background p-2 text-center",
                    result === "correct" && "border-emerald-300/70 bg-emerald-300/10",
                    result === "wrong" && "border-destructive/70 bg-destructive/10",
                    result === "unknown" && "border-dashed border-muted-foreground/40",
                  )}
                  key={slot}
                  title={resultLabel(result)}
                >
                  <RequiemIcon className="mx-auto size-16" mod={attempt.mods[slot]} />
                  <p className="mt-1 text-sm font-medium">{attempt.mods[slot] || `S${slot + 1}`}</p>
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  ) : null;

  const activeAttemptContent = (
    <div className="space-y-4">
      {sequencePanel}
      {attemptWorkspace}
    </div>
  );

  const reasonPanel = (
    <div className="space-y-2">
      {recommendation.reason.map((reason) => (
        <div className="rounded-md bg-muted/50 p-2 text-sm text-muted-foreground" key={reason}>
          {reason}
        </div>
      ))}
    </div>
  );

  const first = state.known[0];
  const second = state.known[1];
  const third = state.known[2];
  const progressDock = (
    <aside className="rounded-lg border bg-card/95 p-3 shadow-lg ring-1 ring-foreground/10 backdrop-blur lg:sticky lg:top-3">
      <div className="space-y-4">
        <div>
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Открытые слова
          </p>
          <div className="flex flex-wrap gap-2">
            {[0, 1, 2].map((slot) => {
              const mod = state.known[slot];

              return (
                <div className="flex items-center gap-1.5 rounded-md border bg-input/20 px-2 py-1 text-sm" key={slot}>
                  <span className="text-muted-foreground">{slot + 1}</span>
                  <RequiemIcon className="size-6" mod={mod || ""} />
                  <span>{mod || "?"}</span>
                </div>
              );
            })}
          </div>
        </div>

        <div>
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Верная часть / текущий порядок
          </p>
          {isSolved && (
            <Badge className="mb-2 border-emerald-300/70 bg-emerald-300/15 text-emerald-200" variant="outline">
              Sequence solved
            </Badge>
          )}
          <div className="flex flex-wrap gap-2">
            {[0, 1, 2].map((slot) => {
              const fixed = analysis.fixed[slot];
              const recommended = solvedAttempt?.mods[slot] ?? recommendation.sequence[slot];
              const displayed = fixed || (recommended === "любой" ? state.trialMods[slot] || "?" : recommended);

              return (
                <div
                  className={cn(
                    "flex items-center gap-1.5 rounded-md border bg-input/20 px-2 py-1 text-sm",
                    fixed && "border-primary bg-primary/10 text-primary",
                  )}
                  key={slot}
                >
                  <span className="text-muted-foreground">S{slot + 1}</span>
                  <RequiemIcon className="size-6" mod={displayed} />
                  <span>{displayed}</span>
                </div>
              );
            })}
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          <Button
            disabled={!state.known.length && !state.attempts.length && !draftAttempt}
            onClick={resetAll}
            size="xs"
            type="button"
            variant="destructive"
          >
            Reset all
          </Button>
        </div>
        {attemptHistory}
      </div>
    </aside>
  );
  const roadmapSteps: Array<{ content: ReactNode; text: string; title: string }> = [
    {
      title: first ? `1-е слово открыто: ${first}` : "Набить первый Requiem",
      text: first
        ? "Первое murmur-слово сохранено. Если ошибся словом, поменяй его здесь, следующие шаги пересоберутся."
        : "Иди в миссии лича и добивай thralls через Mercy. Самого лича пока не stab: положи 3 раза и отпусти.",
      content: first ? null : revealPicker(0),
    },
  ];

  if (first) {
    roadmapSteps.push({
      title: `Проверить ${first} в 1 слоте`,
      text: `Поставь ${first} в первый слот, затем Oull или выбранный filler в неизвестные слоты. После Mercy сразу запиши результат здесь.`,
      content: !second && state.attempts.length === 0 ? activeAttemptContent : null,
    });
  }

  if (state.attempts.length > 0 || second) {
    roadmapSteps.push({
      title: second ? `2-е слово открыто: ${second}` : "Набить второй Requiem",
      text: second
        ? "Второе murmur-слово сохранено. Теперь helper может проверять перестановки двух известных слов."
        : "После первой stab-попытки продолжай миссии лича и thralls, пока шкала murmur не откроет второе слово.",
      content: second ? null : revealPicker(1),
    });
  }

  if (second) {
    roadmapSteps.push({
      title: `Проверить порядок ${first} / ${second}`,
      text: "Поставь предложенную комбинацию в Parazon. Если слот стал красным, следующие слоты игра не проверила.",
      content: !third && state.attempts.length <= 1 ? activeAttemptContent : null,
    });
  }

  if (!isSolved && ((second && state.attempts.length > 1) || third)) {
    roadmapSteps.push({
      title: third ? `3-е слово открыто: ${third}` : "Набить третий Requiem",
      text: third
        ? "Все три murmur-слова сохранены. Осталось только добрать правильный порядок."
        : "Если порядок ещё не найден через Oull и попытки, добей murmur до третьего слова.",
      content: third ? null : revealPicker(2),
    });
  }

  if (third || isSolved) {
    roadmapSteps.push({
      title: isSolved ? "Комбинация найдена" : "Добрать финальный порядок",
      text: isSolved
        ? "Все три слота уже дали зелёный результат. Если в комбинации есть Oull, третий Requiem можно не открывать."
        : "Теперь больше не угадываем слова, а только переставляем известные Requiem по красным и белым результатам.",
      content: (
        <div className="space-y-4">
          {sequencePanel}
          {attemptWorkspace}
          {!isSolved && reasonPanel}
        </div>
      ),
    });
  }

  return (
    <main className="mx-auto min-h-screen w-full max-w-6xl px-4 py-8 sm:px-6">
      <header className="mb-6 text-center">
        <Badge variant="outline" className="mb-3 border-primary/30 text-primary">
          Kuva Lich / Sister planner
        </Badge>
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">Requiem Helper</h1>
        <p className="mx-auto mt-3 max-w-2xl text-base text-muted-foreground">
          Один последовательный роудмап: открыл слова, поставил порядок, сделал Mercy,
          записал результат, получил следующий порядок.
        </p>
      </header>

      <Dialog open={Boolean(confirmAction)} onOpenChange={(open) => !open && setConfirmAction(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{confirmAction?.title}</DialogTitle>
            <DialogDescription>{confirmAction?.description}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button onClick={() => setConfirmAction(null)} type="button" variant="outline">
              Cancel
            </Button>
            <Button
              onClick={() => {
                confirmAction?.onConfirm();
                setConfirmAction(null);
              }}
              type="button"
              variant="destructive"
            >
              {confirmAction?.confirmLabel}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start">
        <ol className="relative space-y-4 before:absolute before:left-3.5 before:top-4 before:h-[calc(100%-2rem)] before:w-px before:bg-border">
          {roadmapSteps.map((step, index) => (
            <RoadmapStep
              index={index}
              key={step.title}
              status={stepStatus(index, roadmapSteps.length - 1)}
              text={step.text}
              title={step.title}
            >
              {step.content}
            </RoadmapStep>
          ))}
        </ol>
        {progressDock}
      </div>
    </main>
  );
}

export default App;
