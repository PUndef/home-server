export const REQUIEMS = ["Fass", "Jahu", "Khra", "Lohk", "Netra", "Ris", "Vome", "Xata"] as const;
export const ALL_REQUIEMS = [...REQUIEMS, "Oull"] as const;

export type Requiem = (typeof REQUIEMS)[number];
export type SlotMod = Requiem | "Oull" | "";
export type AttemptResult = "unknown" | "correct" | "wrong";

export type Attempt = {
  id: string;
  mods: [SlotMod, SlotMod, SlotMod];
  results: [AttemptResult, AttemptResult, AttemptResult];
};

export type HelperState = {
  known: Requiem[];
  hasOull: boolean;
  trialMods: [SlotMod, SlotMod, SlotMod];
  attempts: Attempt[];
};

export type Analysis = {
  fixed: Array<Requiem | null>;
  banned: Array<Set<Requiem>>;
  notes: string[];
};

export type Recommendation = {
  summary: string;
  sequence: string[];
  reason: string[];
};

export type FlowStep = {
  title: string;
  text: string;
};

export const defaultState: HelperState = {
  known: [],
  hasOull: true,
  trialMods: ["", "", ""],
  attempts: [],
};

function generateId(): string {
  const cryptoObj = typeof crypto !== "undefined" ? crypto : undefined;
  if (cryptoObj?.randomUUID) {
    return cryptoObj.randomUUID();
  }
  if (cryptoObj?.getRandomValues) {
    const bytes = new Uint8Array(16);
    cryptoObj.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }
  return `id-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export function createAttempt(mods: Attempt["mods"] = ["", "", ""]): Attempt {
  return {
    id: generateId(),
    mods,
    results: ["unknown", "unknown", "unknown"],
  };
}

export function analyzeAttempts(attempts: Attempt[]): Analysis {
  const fixed: Array<Requiem | null> = [null, null, null];
  const banned: Array<Set<Requiem>> = [new Set(), new Set(), new Set()];
  const notes: string[] = [];

  attempts.forEach((attempt) => {
    attempt.mods.forEach((mod, slot) => {
      const result = attempt.results[slot];

      if (!mod || mod === "Oull" || result === "unknown") return;

      if (result === "correct") {
        fixed[slot] = mod;
      }

      if (result === "wrong") {
        banned[slot].add(mod);
      }
    });
  });

  fixed.forEach((mod, slot) => {
    if (mod) notes.push(`${mod} уже подтверждён в слоте ${slot + 1}.`);
  });

  banned.forEach((mods, slot) => {
    if (mods.size) notes.push(`Слот ${slot + 1}: не подходят ${[...mods].join(", ")}.`);
  });

  return { fixed, banned, notes };
}

function validCandidate(candidate: string[], analysis: Analysis) {
  return candidate.every((mod, slot) => {
    if (analysis.fixed[slot] && analysis.fixed[slot] !== mod) return false;
    if (mod !== "?" && analysis.banned[slot].has(mod as Requiem)) return false;
    return true;
  });
}

function permutations<T>(items: T[]): T[][] {
  if (items.length <= 1) return [items];

  return items.flatMap((item, index) => {
    const rest = items.filter((_, restIndex) => restIndex !== index);
    return permutations(rest).map((perm) => [item, ...perm]);
  });
}

function scoreCandidate(candidate: string[], analysis: Analysis) {
  return candidate.reduce((score, mod, slot) => {
    let nextScore = score;

    if (analysis.fixed[slot] === mod) nextScore += 30;
    if (mod !== "?") nextScore += 10 - slot;
    if (mod !== "?" && !analysis.banned[slot].has(mod as Requiem)) nextScore += 3;

    return nextScore;
  }, 0);
}

export function recommend(state: HelperState): Recommendation {
  const known = state.known.slice(0, 3);
  const analysis = analyzeAttempts(state.attempts);

  if (known.length === 0) {
    return {
      summary: "Сначала фарми thralls, пока не откроется первый Requiem.",
      sequence: ["не Mercy", "убивать thralls", "ждать 1-й мод"],
      reason: [
        "До первого открытого Requiem ты не знаешь ни одного настоящего слова, поэтому stab почти всегда просто поднимет уровень лича.",
        "Если лич пришёл сейчас, положи его 3 раза и не делай Mercy. Так rage не сбросится, и он с высокой вероятностью придёт снова.",
        "В Parazon можешь держать что угодно, но осмысленный порядок появится только после первого открытого мода.",
      ],
    };
  }

  const placeholders = Array.from({ length: 3 - known.length }, () => "?");
  const candidates = permutations([...known, ...placeholders])
    .filter((candidate) => validCandidate(candidate, analysis))
    .sort((a, b) => scoreCandidate(b, analysis) - scoreCandidate(a, analysis));

  let usedOull = false;
  const sequence = (candidates[0] || [...known, ...placeholders].slice(0, 3)).map((mod) => {
    if (mod !== "?") return mod;

    if (state.hasOull && !usedOull) {
      usedOull = true;
      return "Oull";
    }

    return "любой";
  });

  const reason = [...analysis.notes];

  if (known.length === 1) {
    reason.push("Теперь уже можно делать Mercy: мы проверяем первый открытый мод в первом возможном слоте.");
    reason.push("Oull закрывает неизвестный Requiem. Если Oull нет, третий слот пока почти не важен.");
    reason.push("Если первый мод красный, занеси попытку сюда: helper переставит его дальше.");
  } else if (known.length === 2) {
    reason.push("Два известных мода + Oull позволяют проверять порядок, не ожидая третий мод.");
    reason.push("Если лич пришёл, уже обычно выгодно делать Mercy и записывать результат.");
  } else {
    reason.push("Все три Requiem известны. Теперь не фармишь слова, а только добираешь правильный порядок по красным/белым слотам.");
  }

  return {
    summary: `Открыто Requiem: ${known.join(", ")}${state.hasOull ? " + Oull" : ""}.`,
    sequence,
    reason,
  };
}

export function getActiveStep(state: HelperState) {
  const knownCount = state.known.length;
  const attemptCount = state.attempts.length;

  if (knownCount === 0) return 0;
  if (knownCount === 1 && attemptCount === 0) return 1;
  if (knownCount === 1) return 2;
  if (knownCount === 2 && attemptCount < 2) return 3;
  return 4;
}

export function buildFlowSteps(state: HelperState): FlowStep[] {
  const first = state.known[0] || "первый мод";
  const second = state.known[1] || "второй мод";
  const wildcard = state.hasOull ? "Oull" : "любой";
  const thirdTrial = state.trialMods[2] || "выбранный рандом";

  return [
    {
      title: "Набить первый Requiem",
      text: "Иди в миссии лича и добивай thralls через Mercy. Самого лича пока не stab: положи 3 раза и отпусти.",
    },
    {
      title: `Проверить ${first} в 1 слоте`,
      text: `Когда лич придёт после открытия первого слова, поставь ${first} / ${wildcard} / ${thirdTrial} и сделай Mercy.`,
    },
    {
      title: "Набить второй Requiem",
      text: "После первой проверки продолжай миссии лича и thralls, пока игра не откроет второе слово.",
    },
    {
      title: `Проверить пару ${first} / ${second}`,
      text: `С двумя словами helper переставляет их и закрывает неизвестный слот через ${wildcard}. Записывай красный/белый результат.`,
    },
    {
      title: "Добрать порядок",
      text: "Когда известны 3 слова или достаточно результатов с Oull, просто следуй следующей комбинации справа.",
    },
  ];
}
