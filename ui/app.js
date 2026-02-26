const input = document.querySelector("#videoId");
const submitBtn = document.querySelector("#submitBtn");
const statusEl = document.querySelector("#status");
const transcriptEl = document.querySelector("#transcript");
const copyBtn = document.querySelector("#copyBtn");
const downloadTxtBtn = document.querySelector("#downloadTxtBtn");
const downloadPdfBtn = document.querySelector("#downloadPdfBtn");
const summaryEl = document.querySelector("#summary");
const summarizeBtn = document.querySelector("#summarizeBtn");
const downloadSummaryBtn = document.querySelector("#downloadSummaryBtn");
if (!input || !submitBtn || !statusEl || !transcriptEl || !copyBtn || !downloadTxtBtn || !downloadPdfBtn || !summaryEl || !summarizeBtn || !downloadSummaryBtn) {
  throw new Error("UI elements not found.");
}
const setStatus = (message) => {
  statusEl.textContent = message;
};
const setLoading = (loading) => {
  submitBtn.disabled = loading;
  input.disabled = loading;
};
const setActionsEnabled = (enabled) => {
  copyBtn.disabled = !enabled;
  downloadTxtBtn.disabled = !enabled;
  downloadPdfBtn.disabled = !enabled;
};
const setSummaryActionsEnabled = (loading) => {
  summarizeBtn.disabled = loading || !transcriptEl.value.trim();
  downloadSummaryBtn.disabled = loading || !summaryEl.value.trim();
};
const fetchTranscript = async (videoId) => {
  const response = await fetch(`/api/transcript?video_id=${encodeURIComponent(videoId)}`);
  const payload = await response.json();
  if (!response.ok || "error" in payload) {
    const message = "error" in payload ? payload.error : "Unknown error";
    throw new Error(message);
  }
  return payload.transcript;
};
const fetchSummary = async (text, videoId) => {
  const response = await fetch("/api/summarize", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, video_id: videoId }),
  });
  const payload = await response.json();
  if (!response.ok || "error" in payload) {
    const message = "error" in payload ? payload.error : "Unknown error";
    throw new Error(message);
  }
  return payload.summary;
};
const createDownloadLink = (blob, filename) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
};
const wrapText = (text, maxChars) => {
  const words = text.split(/\s+/).filter(Boolean);
  const lines = [];
  let current = "";
  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length > maxChars) {
      if (current) {
        lines.push(current);
        current = word;
      } else {
        lines.push(word.slice(0, maxChars));
        current = word.slice(maxChars);
      }
    } else {
      current = next;
    }
  }
  if (current) {
    lines.push(current);
  }
  return lines.length ? lines : [""];
};
const escapePdfText = (text) => text.replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)");
const buildPdfBlob = (text, title) => {
  const lines = wrapText(text, 90);
  const linesPerPage = 48;
  const pages = [];
  for (let i = 0; i < lines.length; i += linesPerPage) {
    pages.push(lines.slice(i, i + linesPerPage));
  }
  const objects = [];
  const pageObjectIds = pages.map((_, index) => 5 + index * 2);
  objects.push("<< /Type /Catalog /Pages 2 0 R >>");
  objects.push(`<< /Type /Pages /Kids [${pageObjectIds.map((id) => `${id} 0 R`).join(" ")}] /Count ${pageObjectIds.length} >>`);
  objects.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  pages.forEach((pageLines, index) => {
    const content = [
      "BT",
      "/F1 11 Tf",
      "50 760 Td",
      ...pageLines.map((line, index) => {
        const escaped = escapePdfText(line);
        return `${index === 0 ? "" : "0 -14 Td\n"}(${escaped}) Tj`;
      }),
      "ET",
    ].join("\n");
    const contentStream = `<< /Length ${new TextEncoder().encode(content).length} >>\nstream\n${content}\nendstream`;
    objects.push(contentStream);
    const contentObjectId = 4 + index * 2;
    const pageObjectId = contentObjectId + 1;
    objects.push(
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentObjectId} 0 R >>`,
    );
  });
  const header = "%PDF-1.4\n";
  const parts = [header];
  const offsets = [0];
  let offset = new TextEncoder().encode(header).length;
  objects.forEach((obj, index) => {
    const objId = index + 1;
    const entry = `${objId} 0 obj\n${obj}\nendobj\n`;
    offsets.push(offset);
    offset += new TextEncoder().encode(entry).length;
    parts.push(entry);
  });
  const xrefStart = offset;
  const xrefEntries = offsets
    .map((pos, index) => index === 0 ? "0000000000 65535 f " : `${pos.toString().padStart(10, "0")} 00000 n `)
    .join("\n");
  const trailer = `xref\n0 ${objects.length + 1}\n${xrefEntries}\ntrailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Info << /Title (${escapePdfText(title)}) >> >>\nstartxref\n${xrefStart}\n%%EOF`;
  parts.push(trailer);
  return new Blob(parts, { type: "application/pdf" });
};
let lastVideoId = "";
const handleSubmit = async () => {
  const videoId = input.value.trim();
  if (!videoId) {
    setStatus("Enter a YouTube video ID.");
    input.focus();
    return;
  }
  setLoading(true);
  setStatus("Fetching transcript...");
  transcriptEl.value = "";
  summaryEl.value = "";
  setActionsEnabled(false);
  setSummaryActionsEnabled(true);
  try {
    const transcript = await fetchTranscript(videoId);
    transcriptEl.value = transcript;
    lastVideoId = videoId;
    setActionsEnabled(Boolean(transcript));
    setSummaryActionsEnabled(false);
    setStatus(`Done. Transcript length: ${transcript.length.toLocaleString()} characters.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Request failed.";
    setStatus(`Error: ${message}`);
  } finally {
    setLoading(false);
  }
};
submitBtn.addEventListener("click", handleSubmit);
input.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    handleSubmit();
  }
});
copyBtn.addEventListener("click", async () => {
  const text = transcriptEl.value;
  if (!text) {
    setStatus("Nothing to copy yet.");
    return;
  }
  try {
    await navigator.clipboard.writeText(text);
    setStatus("Transcript copied to clipboard.");
  } catch {
    setStatus("Copy failed. Select and copy manually.");
  }
});
downloadTxtBtn.addEventListener("click", () => {
  const text = transcriptEl.value;
  if (!text) {
    setStatus("Nothing to download yet.");
    return;
  }
  const filename = `${lastVideoId || "transcript"}.txt`;
  createDownloadLink(new Blob([text], { type: "text/plain" }), filename);
  setStatus("TXT downloaded.");
});
downloadPdfBtn.addEventListener("click", () => {
  const text = transcriptEl.value;
  if (!text) {
    setStatus("Nothing to download yet.");
    return;
  }
  const filename = `${lastVideoId || "transcript"}.pdf`;
  const pdfBlob = buildPdfBlob(text, `Transcript ${lastVideoId || ""}`.trim());
  createDownloadLink(pdfBlob, filename);
  setStatus("PDF downloaded.");
});
summarizeBtn.addEventListener("click", async () => {
  const text = transcriptEl.value;
  if (!text) {
    setStatus("Generate a transcript first.");
    return;
  }
  setSummaryActionsEnabled(true);
  setStatus("Summarizing...");
  summaryEl.value = "";
  try {
    const summary = await fetchSummary(text, lastVideoId);
    summaryEl.value = summary;
    setSummaryActionsEnabled(false);
    setStatus("Summary ready.");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Request failed.";
    setStatus(`Error: ${message}`);
    setSummaryActionsEnabled(false);
  }
});
downloadSummaryBtn.addEventListener("click", () => {
  const text = summaryEl.value;
  if (!text) {
    setStatus("Nothing to download yet.");
    return;
  }
  const filename = `${lastVideoId || "summary"}.summary.txt`;
  createDownloadLink(new Blob([text], { type: "text/plain" }), filename);
  setStatus("Summary downloaded.");
});
setActionsEnabled(false);
setSummaryActionsEnabled(false);
