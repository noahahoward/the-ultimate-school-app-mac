import Foundation
import CoreGraphics

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which path produced a draft, so the review sheet can say so plainly.
enum ExtractionEngine: String, Sendable {
    case model = "on-device model"
    case labels = "label matching"

    var explanation: String {
        switch self {
        case .model: "Read on this Mac by Apple's on-device model. Nothing was uploaded."
        case .labels: "Read by matching labels in the screenshot. No model was used."
        }
    }
}

struct ExtractionOutcome: Sendable {
    var draft: ImportDraft
    var engine: ExtractionEngine
    var ocrText: String
}

/// Screenshot in, proposed assignment out.
///
/// The pipeline is deliberately lopsided: Vision reads every pixel of text, the
/// model does nothing but say which of that text belongs in which slot, and Swift
/// does every interpretation. A slot only survives if its text is found in the
/// screenshot, so an answer the model made up cannot reach the database.
enum ScreenshotExtractor {

    static func extract(from image: CGImage, now: Date = Date()) async -> Result<ExtractionOutcome, Error> {
        do {
            let ocr = try ScreenshotOCR.read(image)

            var engine = ExtractionEngine.labels
            var fields = HeuristicExtractor.extract(from: ocr)

            if let modelFields = await modelFields(for: ocr.text) {
                fields = merge(model: modelFields, fallback: fields)
                engine = .model
            }

            let checked = EvidenceCheck.verify(fields, against: ocr.text)
            let draft = FieldParsing.draft(from: checked.fields, rejected: checked.rejected, now: now)
            return .success(ExtractionOutcome(draft: draft, engine: engine, ocrText: ocr.text))
        } catch {
            return .failure(error)
        }
    }

    /// The model leads, but anything it left blank falls back to label matching
    /// rather than being lost.
    static func merge(model: ExtractedFields, fallback: ExtractedFields) -> ExtractedFields {
        var merged = model
        if merged.title.isEmpty { merged.title = fallback.title }
        if merged.teacher.isEmpty { merged.teacher = fallback.teacher }
        if merged.className.isEmpty { merged.className = fallback.className }
        if merged.dueDateText.isEmpty { merged.dueDateText = fallback.dueDateText }
        if merged.assignedDateText.isEmpty { merged.assignedDateText = fallback.assignedDateText }
        if merged.pointsText.isEmpty { merged.pointsText = fallback.pointsText }
        if merged.statusText.isEmpty { merged.statusText = fallback.statusText }
        if merged.attachments.isEmpty { merged.attachments = fallback.attachments }
        return merged
    }

    static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Nil whenever the model is unavailable or declines, which leaves the
    /// label-matched fields in place instead of failing the import.
    private static func modelFields(for ocrText: String) async -> ExtractedFields? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await ModelSlotFiller.fill(ocrText: ocrText)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)

/// The hard slots, as a schema the decoder is constrained to.
///
/// Guided generation means these field names and types are not a suggestion: the
/// model physically cannot return a different shape, so there is no free-form
/// output to misparse.
@available(macOS 26.0, *)
@Generable(description: "Fields copied verbatim from a screenshot of school software.")
struct AssignmentSlots {

    @Guide(description: "The assignment's title, copied exactly. Empty if none is shown.")
    var title: String

    @Guide(description: "The teacher's name, copied exactly. Empty if none is shown.")
    var teacher: String

    @Guide(description: "The class or course name, copied exactly. Empty if none is shown.")
    var className: String

    @Guide(description: "The due date exactly as printed, such as 'Due Aug 26'. Do not convert it. Empty if no due date is shown.")
    var dueDateText: String

    @Guide(description: "The date it was posted or assigned, exactly as printed. Empty if none is shown.")
    var assignedDateText: String

    @Guide(description: "The points value exactly as printed, such as '4 points'. Empty if none is shown.")
    var pointsText: String

    @Guide(description: "The submission status exactly as printed, such as 'Assigned' or 'Turned in'. Empty if none is shown.")
    var statusText: String

    @Guide(description: "The name printed on each attachment card, copied exactly. Use the file's name, never its type — do not answer 'Google Docs', 'PDF', or 'Google Slides'. Empty if nothing is attached.")
    var attachments: [String]

    @Guide(description: "One plain sentence describing the assignment itself, using only what the text shows. Never describe buttons, comment boxes, or other controls. Empty if the text says nothing about the work.")
    var summary: String
}

@available(macOS 26.0, *)
enum ModelSlotFiller {

    /// Copy, never compose. The prompt says it, the schema shapes it, and
    /// `EvidenceCheck` is what actually enforces it afterwards.
    static let instructions = """
        You are labelling text that was read from a screenshot of school software \
        such as Google Classroom, Canvas, or Skyward.

        Rules:
        - Copy text exactly as it appears. Never reword, correct, translate, or reformat it.
        - Never work anything out. Do not convert a date, do not add a year, do not do arithmetic.
        - If the text does not clearly show a field, leave that field empty.
        - An empty field is always better than a guess.
        - The only field you write yourself is the summary, and it may only restate \
        what the text already says.
        """

    static func fill(ocrText: String) async -> ExtractedFields? {
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        // Greedy decoding: the same screenshot yields the same answer every time.
        let options = GenerationOptions(sampling: .greedy)

        let prompt = """
            Here is every line of text read from the screenshot, in order:

            \(ocrText)

            Fill in the fields using only that text.
            """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: AssignmentSlots.self,
                options: options
            )
            let slots = response.content
            return ExtractedFields(
                title: slots.title,
                teacher: slots.teacher,
                className: slots.className,
                dueDateText: slots.dueDateText,
                assignedDateText: slots.assignedDateText,
                pointsText: slots.pointsText,
                statusText: slots.statusText,
                attachments: slots.attachments,
                summary: slots.summary
            )
        } catch {
            // A refusal, a guardrail trip, or no model: fall back rather than fail.
            return nil
        }
    }
}

#endif
