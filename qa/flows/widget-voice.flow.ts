import { expect, test } from "../lib/proof.ts";

// The recorder times itself with the real clock. The microphone is a tone whose loudness swings,
// so the recording and its live wave have something to show.
test.use({
  target: "widget",
  fixedClock: false,
  launchOptions: { slowMo: Number(process.env.QA_SLOWMO ?? 250), args: ["--autoplay-policy=no-user-gesture-required"] },
});

test.beforeEach(async ({ page }) => {
  // Only the widget on screen. The text stays in the DOM: the recorder starts at the first text.
  await page.addInitScript(() => {
    document.addEventListener("DOMContentLoaded", () => {
      document.head.insertAdjacentHTML("beforeend", "<style>main { opacity: 0; }</style>");
    });
  });
  await page.addInitScript(() => {
    navigator.mediaDevices.getUserMedia = async () => {
      const ctx = new AudioContext();
      const tone = new OscillatorNode(ctx, { frequency: 220 });
      const level = new GainNode(ctx, { gain: 0.5 });
      const swing = new OscillatorNode(ctx, { frequency: 0.8 });
      const depth = new GainNode(ctx, { gain: 0.45 });
      swing.connect(depth).connect(level.gain);
      const out = new MediaStreamAudioDestinationNode(ctx);
      tone.connect(level).connect(out);
      tone.start();
      swing.start();
      return out.stream;
    };
  });
});

test("record, listen back and send a voice message from the widget", async ({ page, proof }) => {
  await proof.open();
  await page.getByRole("button", { name: "Open chat" }).click();
  const chat = page.getByRole("dialog", { name: /^Chat with/ });
  await chat.getByRole("button", { name: "Send us a message" }).click();
  const record = chat.getByRole("button", { name: "Record a voice message" });
  await expect(record).toBeVisible();
  await proof.chapter("Voice messages", "Record from the microphone, listen back, then send");
  await proof.shot("composer", { caption: "The microphone beside Send", target: chat });

  await record.click();
  const bar = chat.getByRole("timer", { name: "Recording" });
  await expect(bar).toBeVisible();
  await proof.dwell(2500);
  await proof.shot("recording", { caption: "Recording: cancel, the time, a live sound wave and stop", target: chat, ignore: [bar] });

  await chat.getByRole("button", { name: "Stop recording" }).click();
  await expect(chat.getByRole("button", { name: "Delete the recording" })).toBeVisible();
  await proof.shot("recorded", { caption: "The recording waits above the field, ready to play or delete", target: chat });

  await chat.getByRole("button", { name: "Send" }).click();
  await expect(chat.getByRole("button", { name: "Play voice message" }).last()).toBeVisible();
  await proof.dwell();
  await proof.shot("sent", { caption: "Sent, with a player in the thread", target: chat });
});
