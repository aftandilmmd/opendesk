// Settings > AI agent > Behaviour (contracts/agent.md): turn the widget agent
// on, see which bots it answers as, pick its model and set guardrails. Names,
// looks and personalities live on the bots (Settings > AI agent > Bots).
// Unsaved edits travel to the playground so they can be tried before they are saved.

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate } from "@tanstack/react-router";
import { ChevronRight, ClipboardCheck, FlaskConical } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { NoAccess, Row, Section, SettingsPage } from "@/components/layout";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { toast } from "@/components/ui/toast";
import { Stepper } from "@/components/settings2/Stepper";
import { IconTile } from "@/components/settings2/bits";
import { SaveBar } from "@/components/settings/SaveBar";
import { UnsavedGuard } from "@/components/settings2/UnsavedGuard";
import { OllieMark } from "@/components/assistant/OllieMark";
import { ModelPicker } from "@/components/ai/ModelPicker";
import { ChipEditor } from "@/components/agent/ChipEditor";
import { EmailMailboxes } from "@/components/agent/EmailMailboxes";
import { UsdField } from "@/components/agent/bits";
import { agentSettings, playgroundSettings, CAP_MAX, TOPICS_MAX, topicProblem, useAgentDraft, type AgentSettings } from "@/components/agent/settings";
import { BotFace } from "@/components/bots/BotFace";
import { useUsageLine } from "@/components/bots/bits";
import { api } from "@/lib/api/endpoints";
import type { AIConfig, AISettings } from "@/lib/api/types";
import { q, qk } from "@/lib/queries";
import { atLeast, useRole } from "@/lib/session";
import { AI_TONE, tone } from "@/lib/tones";
import { cn } from "@/lib/cn";
import { sameJSON } from "@/lib/sameJSON";

const PLAYGROUND = "/settings/ai/playground";
const TESTS = "/settings/ai/tests";

export default function AgentBehaviour() {
  const { t } = useTranslation("agent");
  const admin = atLeast(useRole(), "admin");
  const { data: config, isLoading } = useQuery(q.aiConfig());
  const { data: models } = useQuery({ ...q.aiModels(), enabled: admin && !!config?.enabled });
  const qc = useQueryClient();
  const kept = useAgentDraft((s) => s.draft);
  const setKept = useAgentDraft((s) => s.setDraft);

  const base = useMemo(() => agentSettings(config?.features), [config?.features]);
  const [draft, setDraft] = useState<AgentSettings>(() => kept?.ai ?? base);
  const [touched, setTouched] = useState(!!kept);

  // Follow the server until the first edit (realtime, the first load).
  useEffect(() => {
    if (!touched) setDraft(base);
  }, [base, touched]);

  const dirty = !sameJSON(draft, base);
  // Unsaved edits stay available to the playground, and come back here.
  useEffect(() => {
    setKept(dirty ? { ai: draft } : null);
  }, [dirty, draft, setKept]);

  const set = (p: Partial<AgentSettings>) => {
    setTouched(true);
    setDraft((d) => ({ ...d, ...p }));
  };

  const save = useMutation({
    mutationFn: async () => {
      const patch: Partial<AISettings> = {};
      for (const k of Object.keys(draft) as (keyof AgentSettings)[]) {
        if (!sameJSON(draft[k], base[k])) (patch as Record<string, unknown>)[k] = draft[k];
      }
      return Object.keys(patch).length ? api.ai.updateSettings(patch) : null;
    },
    onSuccess: (features) => {
      if (features) qc.setQueryData<AIConfig | null>(qk.aiConfig, (old) => (old ? { ...old, features } : old));
      setTouched(false);
      setKept(null);
      toast.success(t("behaviour.saved"));
    },
    onError: (e) => toast.error(e, t("behaviour.saveError")),
  });

  // Run the agent's tests, against these edits when there are any.
  const { t: tq } = useTranslation("agentQuality");
  const navigate = useNavigate();
  const runTests = useMutation({
    mutationFn: () => api.ai.agent.runs.start({ settings: dirty ? playgroundSettings({ ai: draft }) : undefined }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: qk.agentTestRuns });
      void navigate({ to: TESTS });
    },
    onError: (e) => toast.error(e, tq("behaviour.runError")),
  });

  const discard = () => {
    setDraft(base);
    setTouched(false);
    setKept(null);
  };

  if (!admin)
    return (
      <SettingsPage title={t("behaviour.title")}>
        <NoAccess what={t("behaviour.what")} />
      </SettingsPage>
    );

  const defaultModel = config?.features?.model || config?.models.default || models?.default || "";
  const off = !draft.widget_answers;

  return (
    <SettingsPage
      title={t("behaviour.title")}
      description={t("behaviour.description")}
      actions={
        <>
          <Button icon={<ClipboardCheck className="size-3.5 text-fg-3" />} loading={runTests.isPending} onClick={() => runTests.mutate()}>
            {dirty ? tq("behaviour.runTestsDraft") : tq("behaviour.runTests")}
          </Button>
          <Button asChild>
            <Link to={PLAYGROUND}>
              <FlaskConical className="size-3.5 text-fg-3" />
              {dirty ? t("behaviour.tryChanges") : t("behaviour.openPlayground")}
            </Link>
          </Button>
        </>
      }
    >
      <UnsavedGuard when={dirty && !save.isPending} allow={(p) => p === PLAYGROUND || p === TESTS} />
      {isLoading || !config ? (
        <div className="flex flex-col gap-3">
          <Skeleton className="h-16 rounded-lg" />
          <Skeleton className="h-48 rounded-lg" />
        </div>
      ) : (
        <>
          <Section>
            <div className="flex items-center gap-3.5 py-3.5">
              <IconTile tone={off ? "gray" : AI_TONE} className="size-9 transition-colors duration-200">
                <OllieMark size={20} tone={off ? "muted" : "color"} />
              </IconTile>
              <div className="min-w-0 flex-1">
                <label htmlFor="agent-on" className="text-[12.5px] font-medium text-fg">
                  {t("behaviour.enable")}
                </label>
                <div className="mt-0.5 text-[12px] leading-[18px] text-fg-3">{t("behaviour.enableHint")}</div>
              </div>
              <Switch id="agent-on" checked={draft.widget_answers} onCheckedChange={(widget_answers) => set({ widget_answers })} aria-label={t("behaviour.enable")} />
            </div>
          </Section>

          <BotsSummary />

          <Section title={t("behaviour.model")} description={t("behaviour.modelHint")}>
            <Row label={t("behaviour.widgetModel")} description={t("behaviour.widgetModelHint")} stack>
              <ModelPicker
                value={draft.widget_model}
                onChange={(widget_model) => set({ widget_model })}
                models={models?.data}
                defaultId={defaultModel}
                defaultLabel={t("behaviour.sameAsMain")}
                aria-label={t("behaviour.widgetModel")}
                className="max-w-[460px]"
              />
            </Row>
            <Row label={t("behaviour.maxReplies")} description={t("behaviour.maxRepliesHint")}>
              <Stepper
                value={draft.widget_max_replies}
                onChange={(widget_max_replies) => set({ widget_max_replies })}
                min={1}
                max={100}
                aria-label={t("behaviour.maxReplies")}
                suffix={t("behaviour.repliesSuffix")}
                className="w-[150px]"
              />
            </Row>
          </Section>

          <Section title={t("behaviour.guardrails")} description={t("behaviour.guardrailsHint")}>
            <Row label={t("behaviour.topics")} description={t("behaviour.topicsHint")} stack>
              <ChipEditor
                values={draft.widget_blocked_topics}
                onChange={(widget_blocked_topics) => set({ widget_blocked_topics })}
                max={TOPICS_MAX}
                placeholder={t("behaviour.topicsPlaceholder")}
                aria-label={t("behaviour.topics")}
                normalize={(v) => v.trim().replace(/\s+/g, " ")}
                validate={(v) => {
                  const p = topicProblem(v);
                  return p ? t(`behaviour.topic_${p}`) : null;
                }}
                dot="bg-tone-red-solid"
                empty={t("behaviour.topicsEmpty")}
              />
            </Row>
            <Row label={t("behaviour.cap")} description={t("behaviour.capHint")} stack>
              <UsdField
                value={draft.widget_monthly_cap_usd}
                onChange={(widget_monthly_cap_usd) => set({ widget_monthly_cap_usd })}
                max={CAP_MAX}
                presets={[5, 20, 50, 100]}
                zeroLabel={t("behaviour.noCap")}
                aria-label={t("behaviour.cap")}
              />
            </Row>
            <Row label={t("behaviour.collectEmail")} description={t("behaviour.collectEmailHint")}>
              <Switch checked={draft.widget_collect_email} onCheckedChange={(widget_collect_email) => set({ widget_collect_email })} aria-label={t("behaviour.collectEmail")} />
            </Row>
          </Section>

          <EmailMailboxes />
        </>
      )}

      <SaveBar dirty={dirty} saving={save.isPending} onSave={() => save.mutate()} onDiscard={discard} />
    </SettingsPage>
  );
}

/** Who the agent answers as: the workspace's bots and where each one answers (contracts/bots.md). */
function BotsSummary() {
  const { t } = useTranslation("bots");
  const { data: bots } = useQuery(q.bots());
  const usageLine = useUsageLine();
  return (
    <Section
      title={t("summary.title")}
      description={t("summary.hint")}
      flush
      actions={
        <Button size="sm" asChild>
          <Link to="/settings/ai/bots">{t("summary.manage")}</Link>
        </Button>
      }
    >
      {!bots ? (
        <div className="p-4">
          <Skeleton className="h-10 rounded-md" />
        </div>
      ) : (
        bots.slice(0, 4).map((b) => (
          <Link
            key={b.id}
            to="/settings/ai/bots/$botId"
            params={{ botId: b.id }}
            className="group flex min-h-12 items-center gap-3 border-b border-line-soft px-4 py-2.5 transition-colors last:border-0 hover:bg-sunken"
          >
            <BotFace look={b.look} image={b.image_url} size={28} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-[13px] font-medium text-fg">
                <span className="truncate">{b.name}</span>
                {b.is_default && <span className={cn("rounded-sm px-1.5 py-px text-[10.5px] font-medium", tone[AI_TONE].chip)}>{t("list.default")}</span>}
              </div>
              <div className="truncate text-[12px] text-fg-3">{usageLine(b)}</div>
            </div>
            <ChevronRight className="size-3.5 text-fg-4 transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none" />
          </Link>
        ))
      )}
    </Section>
  );
}
