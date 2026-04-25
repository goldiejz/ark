/**
 * Phase 7 Extended: Multi-Model Tier Resolver
 *
 * Extends tier selection to include Claude (Haiku/Sonnet/Opus), Codex, and Gemini.
 * Routes tasks based on:
 * 1. Codebase complexity (Codex strength)
 * 2. Breadth of reasoning (Gemini strength)
 * 3. Cost efficiency (Haiku strength)
 * 4. Coding precision (Sonnet strength)
 * 5. Novel architectural decisions (Opus strength)
 */

export type Model = "haiku" | "sonnet" | "opus" | "codex" | "gemini";
export type ModelProvider = "claude" | "anthropic" | "codex" | "google";

interface ModelCapabilityProfile {
  model: Model;
  provider: ModelProvider;
  costPerKToken: number; // $ per 1000 tokens
  latencyMs: number; // Typical response time
  strengths: string[]; // What this model excels at
  weaknesses: string[]; // What this model struggles with
  bestFor: string[]; // Task types
}

interface TaskCharacteristics {
  taskType: string;
  codebaseLinesOfCode?: number;
  reasoningDepth: "shallow" | "medium" | "deep";
  breadthRequired: "narrow" | "wide" | "universal";
  needsContextAwareness: boolean;
  isCached: boolean;
  pastExecutions: number;
  hasMultiRepoContext?: boolean;
  involvesRefactoring?: boolean;
  requiresCodeReview?: boolean;
}

interface ModelRecommendation {
  taskId: string;
  model: Model;
  provider: ModelProvider;
  reason: string;
  costEstimate: number;
  confidence: number; // 0-1
  alternativeModels: { model: Model; reason: string; costDelta: number }[]; // Other viable options
}

const MODEL_PROFILES: Record<Model, ModelCapabilityProfile> = {
  haiku: {
    model: "haiku",
    provider: "claude",
    costPerKToken: 0.08,
    latencyMs: 2000,
    strengths: ["lightweight queries", "cached responses", "pair programming", "simple transformations"],
    weaknesses: ["deep reasoning", "novel architectural decisions", "large codebase analysis"],
    bestFor: ["cached-bootstrap", "simple-transforms", "lightweight-agents"],
  },

  sonnet: {
    model: "sonnet",
    provider: "claude",
    costPerKToken: 0.2,
    latencyMs: 5000,
    strengths: [
      "balanced reasoning",
      "code generation",
      "multi-file edits",
      "orchestration",
      "context-aware reasoning",
    ],
    weaknesses: ["ultra-deep novel reasoning", "very large codebase (>100K LOC)"],
    bestFor: ["main-dev-work", "code-generation", "multi-file-refactor", "orchestration"],
  },

  opus: {
    model: "opus",
    provider: "claude",
    costPerKToken: 0.4,
    latencyMs: 10000,
    strengths: ["deep novel reasoning", "architectural decisions", "complex problem solving", "research"],
    weaknesses: ["latency-sensitive tasks", "simple queries (overengineered)"],
    bestFor: ["novel-architecture", "deep-research", "novel-contradictions"],
  },

  codex: {
    model: "codex",
    provider: "codex",
    costPerKToken: 0.15,
    latencyMs: 8000,
    strengths: [
      "code generation from spec",
      "large codebase navigation",
      "refactoring",
      "test generation",
      "multi-file coordination",
    ],
    weaknesses: ["pure reasoning tasks", "non-code problem solving"],
    bestFor: ["code-refactor", "test-generation", "large-file-edits", "multi-repo-changes"],
  },

  gemini: {
    model: "gemini",
    provider: "google",
    costPerKToken: 0.075,
    latencyMs: 6000,
    strengths: [
      "broad knowledge synthesis",
      "multimodal reasoning",
      "cross-domain patterns",
      "research synthesis",
      "wide context windows",
    ],
    weaknesses: ["precise code generation", "small-scale edits", "deterministic output"],
    bestFor: ["research-synthesis", "cross-project-patterns", "broad-analysis", "doc-generation"],
  },
};

function analyzeTaskComplexity(task: TaskCharacteristics): {
  codeComplexity: number; // 0-100
  reasoningComplexity: number; // 0-100
  breadthRequirement: number; // 0-100
} {
  const codeComplexity = task.codebaseLinesOfCode
    ? Math.min(100, (task.codebaseLinesOfCode / 100000) * 100)
    : task.involvesRefactoring
      ? 60
      : 30;

  const reasoningComplexity =
    task.reasoningDepth === "deep"
      ? 85
      : task.reasoningDepth === "medium"
        ? 50
        : 20;

  const breadthRequirement =
    task.breadthRequired === "universal"
      ? 100
      : task.breadthRequired === "wide"
        ? 60
        : 20;

  return { codeComplexity, reasoningComplexity, breadthRequirement };
}

function scoreModel(
  model: Model,
  task: TaskCharacteristics
): { score: number; reason: string } {
  const { codeComplexity, reasoningComplexity, breadthRequirement } =
    analyzeTaskComplexity(task);

  const profile = MODEL_PROFILES[model];
  let score = 0;
  let reason = "";

  // Strategy 1: Cached responses → Always Haiku
  if (task.isCached) {
    if (model === "haiku") {
      return { score: 100, reason: "Cached response, optimal for Haiku" };
    } else {
      return { score: 0, reason: "Cached response should use cheaper Haiku" };
    }
  }

  // Strategy 2: Codex for code-heavy tasks
  if (task.involvesRefactoring || task.hasMultiRepoContext) {
    if (model === "codex") {
      score += 40;
      reason += "Multi-file code coordination (Codex strength). ";
    } else if (model === "sonnet") {
      score += 25;
      reason += "Fallback: Sonnet for code work. ";
    } else {
      score -= 20;
    }
  }

  // Strategy 3: Gemini for broad synthesis and cross-project patterns
  if (task.breadthRequired === "universal" && task.pastExecutions > 10) {
    if (model === "gemini") {
      score += 35;
      reason += "Cross-project pattern synthesis (Gemini strength). ";
    } else if (model === "sonnet") {
      score += 15;
    }
  }

  // Strategy 4: Reasoning depth
  if (task.reasoningDepth === "deep" && !task.isCached) {
    if (model === "opus") {
      score += 50;
      reason += "Deep novel reasoning (Opus strength). ";
    } else if (model === "sonnet") {
      score += 30;
      reason += "Sonnet for medium-deep reasoning. ";
    } else if (model === "gemini") {
      score += 25;
      reason += "Gemini for broad reasoning. ";
    } else {
      score -= 30;
    }
  }

  // Strategy 5: Default case: Sonnet for balanced work
  if (score === 0) {
    if (model === "sonnet") {
      score = 50;
      reason = "Balanced default for general development work. ";
    } else if (model === "haiku") {
      score = 30;
    } else {
      score = 20;
    }
  }

  return { score, reason };
}

function resolveMultiModel(
  taskId: string,
  task: TaskCharacteristics
): ModelRecommendation {
  // Score all models
  const scores = Object.keys(MODEL_PROFILES).map((model) => ({
    model: model as Model,
    ...scoreModel(model as Model, task),
  }));

  // Sort by score
  scores.sort((a, b) => b.score - a.score);

  const primary = scores[0];
  const alternatives = scores.slice(1, 3); // Top 2 alternatives

  const primaryProfile = MODEL_PROFILES[primary.model];

  return {
    taskId,
    model: primary.model,
    provider: primaryProfile.provider,
    reason: primary.reason,
    costEstimate: 2000, // Placeholder; would be calculated based on task
    confidence: Math.min(1, primary.score / 100),
    alternativeModels: alternatives.map((alt) => {
      const altProfile = MODEL_PROFILES[alt.model];
      const costDelta = altProfile.costPerKToken - primaryProfile.costPerKToken;
      return {
        model: alt.model,
        reason: alt.reason,
        costDelta,
      };
    }),
  };
}

// Export for integration into Phase 5 bootstrap
export function createMultiModelResolver() {
  return {
    resolveMultiModel,
    analyzeTaskComplexity,
    scoreModel,
    MODEL_PROFILES,
  };
}

// Demo
if (require.main === module) {
  console.log("🎯 Multi-Model Tier Resolver — Codex + Gemini Integration\n");

  const demoTasks: Array<{
    id: string;
    characteristics: TaskCharacteristics;
  }> = [
    {
      id: "bootstrap-scope",
      characteristics: {
        taskType: "bootstrap-section",
        reasoningDepth: "shallow",
        breadthRequired: "narrow",
        needsContextAwareness: false,
        isCached: true,
        pastExecutions: 15,
      },
    },
    {
      id: "refactor-servicedesk",
      characteristics: {
        taskType: "multi-repo-refactor",
        codebaseLinesOfCode: 45000,
        reasoningDepth: "medium",
        breadthRequired: "wide",
        needsContextAwareness: true,
        isCached: false,
        pastExecutions: 3,
        involvesRefactoring: true,
        hasMultiRepoContext: true,
      },
    },
    {
      id: "novel-architecture",
      characteristics: {
        taskType: "architectural-decision",
        reasoningDepth: "deep",
        breadthRequired: "universal",
        needsContextAwareness: true,
        isCached: false,
        pastExecutions: 0,
      },
    },
    {
      id: "cross-customer-synthesis",
      characteristics: {
        taskType: "observability-synthesis",
        reasoningDepth: "medium",
        breadthRequired: "universal",
        needsContextAwareness: true,
        isCached: false,
        pastExecutions: 8,
      },
    },
    {
      id: "test-generation",
      characteristics: {
        taskType: "test-generation",
        codebaseLinesOfCode: 35000,
        reasoningDepth: "shallow",
        breadthRequired: "narrow",
        needsContextAwareness: true,
        isCached: false,
        pastExecutions: 5,
        involvesRefactoring: false,
        requiresCodeReview: true,
      },
    },
  ];

  console.log("Task Routing Recommendations:\n");

  for (const task of demoTasks) {
    const recommendation = resolveMultiModel(task.id, task.characteristics);

    console.log(`  📋 ${task.id}`);
    console.log(`     → ${recommendation.model.toUpperCase()} (${recommendation.provider})`);
    console.log(`     ✓ ${recommendation.reason}`);

    if (recommendation.alternativeModels.length > 0) {
      console.log(`     Alternative options:`);
      for (const alt of recommendation.alternativeModels) {
        const cost = alt.costDelta > 0 ? `+${alt.costDelta.toFixed(3)}` : `${alt.costDelta.toFixed(3)}`;
        console.log(`       • ${alt.model.toUpperCase()}: ${alt.reason} (cost ${cost}/KToken)`);
      }
    }

    console.log("");
  }

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("Model Distribution (Recommended):");
  console.log("  • Haiku: 40% (cached responses, simple tasks)");
  console.log("  • Sonnet: 35% (main dev work, orchestration)");
  console.log("  • Codex: 15% (large refactors, multi-repo changes)");
  console.log("  • Gemini: 8% (cross-project synthesis)");
  console.log("  • Opus: 2% (novel architecture decisions)");
  console.log("");
}
