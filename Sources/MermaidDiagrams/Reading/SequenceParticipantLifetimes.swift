/**
 * File: SequenceParticipantLifetimes.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Which message creates a participant named by `create` and which ends the lifeline of one named by
 *              `destroy`, with Mermaid's checks of the message that follows them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// `create participant C` and `destroy C` while a sequence diagram is read, as Mermaid and Pele treat them. Mermaid
/// checks the message right after the statement: after `create`, it must be to the participant created; else, after
/// `destroy`, from or to the participant destroyed. Pele draws a participant created at the first message after its
/// `create` when that message is to it, and ends a lifeline at the first message after its last `destroy` when that
/// message is from or to it.
struct SequenceParticipantLifetimes {
    /// The participant the last `create` named, until the next message is checked.
    private var lastCreated: String?
    /// The participant the last `destroy` named, until a message is checked against it.
    private var lastDestroyed: String?
    /// The participants created or destroyed since the last message.
    private var creationsSinceLastMessage: [String] = []
    private var destructionsSinceLastMessage: [String] = []
    /// For each participant destroyed so far, the event of the message that ends its lifeline, and which of its ends
    /// the participant is.
    private var destroyingMessageByIdentifier: [String: (eventIndex: Int, isSource: Bool, isTarget: Bool)] = [:]

    mutating func create(_ identifier: String) {
        lastCreated = identifier
        creationsSinceLastMessage.append(identifier)
    }

    /// A later `destroy` of the same participant replaces the earlier one, so the message that one marked no longer
    /// ends the lifeline.
    mutating func destroy(_ identifier: String, events: inout [SequenceEvent]) {
        lastDestroyed = identifier
        destructionsSinceLastMessage.removeAll { destroyed in destroyed == identifier }
        destructionsSinceLastMessage.append(identifier)
        guard let destroying = destroyingMessageByIdentifier.removeValue(forKey: identifier),
              case .message(var message) = events[destroying.eventIndex] else { return }
        if destroying.isSource { message.destroysSource = false }
        if destroying.isTarget { message.destroysTarget = false }
        events[destroying.eventIndex] = .message(message)
    }

    /// Mermaid's check of a message against the last `create`, else the last `destroy`.
    mutating func check(sourceIdentifier: String, targetIdentifier: String, line: Int) throws(MermaidDiagramReadError) {
        if let created = lastCreated {
            lastCreated = nil
            guard targetIdentifier == created else {
                throw .invalidSyntax(line: line, problem: .sequence(.createdParticipantWithoutCreatingMessage(identifier: created)))
            }
        } else if let destroyed = lastDestroyed {
            lastDestroyed = nil
            guard targetIdentifier == destroyed || sourceIdentifier == destroyed else {
                throw .invalidSyntax(line: line, problem: .sequence(.destroyedParticipantWithoutDestroyingMessage(identifier: destroyed)))
            }
        }
    }

    /// The message with what the statements since the last message make of it: it creates its target when that was
    /// created since, and ends the lifeline of its source or target when that was destroyed since.
    mutating func marking(_ message: SequenceMessage, eventIndex: Int, sourceIdentifier: String, targetIdentifier: String) -> SequenceMessage {
        var marked = message
        marked.createsTarget = creationsSinceLastMessage.contains(targetIdentifier)
        for destroyed in destructionsSinceLastMessage where destroyed == sourceIdentifier || destroyed == targetIdentifier {
            if destroyed == sourceIdentifier { marked.destroysSource = true }
            if destroyed == targetIdentifier { marked.destroysTarget = true }
            destroyingMessageByIdentifier[destroyed] = (eventIndex, destroyed == sourceIdentifier, destroyed == targetIdentifier)
        }
        creationsSinceLastMessage.removeAll()
        destructionsSinceLastMessage.removeAll()
        return marked
    }
}
