// The file types a chat widget may take from visitors (contracts/api.md "Widget",
// `attachment_types`). The server holds the same catalog and checks every upload's
// extension and leading bytes against it.

export type FileTypeGroup = "image" | "document" | "spreadsheet" | "presentation" | "media" | "archive";

export const FILE_TYPE_GROUPS: FileTypeGroup[] = ["image", "document", "spreadsheet", "presentation", "media", "archive"];

export const FILE_TYPES: { id: string; group: FileTypeGroup; extensions: string[] }[] = [
  { id: "png", group: "image", extensions: [".png"] },
  { id: "jpg", group: "image", extensions: [".jpg", ".jpeg"] },
  { id: "gif", group: "image", extensions: [".gif"] },
  { id: "webp", group: "image", extensions: [".webp"] },
  { id: "heic", group: "image", extensions: [".heic", ".heif"] },
  { id: "pdf", group: "document", extensions: [".pdf"] },
  { id: "txt", group: "document", extensions: [".txt"] },
  { id: "csv", group: "document", extensions: [".csv"] },
  { id: "rtf", group: "document", extensions: [".rtf"] },
  { id: "doc", group: "document", extensions: [".doc"] },
  { id: "docx", group: "document", extensions: [".docx"] },
  { id: "odt", group: "document", extensions: [".odt"] },
  { id: "xls", group: "spreadsheet", extensions: [".xls"] },
  { id: "xlsx", group: "spreadsheet", extensions: [".xlsx"] },
  { id: "ods", group: "spreadsheet", extensions: [".ods"] },
  { id: "ppt", group: "presentation", extensions: [".ppt"] },
  { id: "pptx", group: "presentation", extensions: [".pptx"] },
  { id: "odp", group: "presentation", extensions: [".odp"] },
  { id: "mp4", group: "media", extensions: [".mp4", ".m4v"] },
  { id: "mov", group: "media", extensions: [".mov"] },
  { id: "mp3", group: "media", extensions: [".mp3"] },
  { id: "m4a", group: "media", extensions: [".m4a"] },
  { id: "wav", group: "media", extensions: [".wav"] },
  { id: "webm", group: "media", extensions: [".webm"] },
  { id: "ogg", group: "media", extensions: [".ogg", ".oga", ".opus"] },
  { id: "zip", group: "archive", extensions: [".zip"] },
];

export const ALL_FILE_TYPES = FILE_TYPES.map((f) => f.id);

/** The extensions of the given types, in catalog order; unknown ids are skipped. */
export function fileTypeExtensions(ids: string[]): string[] {
  return FILE_TYPES.filter((f) => ids.includes(f.id)).flatMap((f) => f.extensions);
}
