# Add to Vault consistency

Both `ItemFormView` and the share extension now use `Shared/AddToVaultForm.swift` and `Shared/VaultTagPicker.swift`. The standard profile preserves Findly's existing preview, title card, tag chips, optional notes, bottom Save button, and brief success confirmation. The two callers retain their separate persistence paths. The extension explains that the saved file enters the vault on the next app opening.

Existing tag colors and symbols, including emoji, are carried in the share catalog. Old catalogs remain readable. The extension follows Findly's last published appearance preference. New tags are assigned an ID when created, never during rendering. Photo previews decode from disk with an 800-pixel maximum dimension. Repeated Save taps are guarded, and presenting the tag picker does not intentionally discard the attachment or reset the title.

## Verification

- Xcode 26.6, Findly scheme, iPhone 17 Pro simulator on iOS 26.5: app and extension built; all 81 tests passed.
- Hosted render inspection: 320 × 640 form in light/dark, default/largest accessibility text; picker in light/dark with long names and an emoji. At large text, content scrolls while Save remains at the bottom.
- Regression coverage includes legacy catalogs, bounded image decoding, file preservation, retry recovery, and replay without duplicate items.
- Shared UI audit: zero high findings; six medium findings reviewed (bounded preview geometry, decorative symbol dimensions, background safe-area coverage). The extension audit's UUID warning is a false positive: it is allocated in the tag-creation action. Its delay warning refers to a cancellable one-second success message, not animation coordination.
- `git diff --check` passed.
- No new physical-device WhatsApp interaction, VoiceOver, keyboard, reduced-effects system-setting, or Instruments session was performed for this revision. Native semantic controls and reduced-motion/transparency branches are present; those runtime checks remain unverified.

Provisional Apple Fidelity evidence score: 79/100 (platform 14/15, layout 13/15, semantics 14/15, interaction 14/20, motion 13/15, accessibility 6/10, implementation/performance 5/10). This is capped by missing interactive and assistive-technology verification, not a claim that all runtime gates passed.

## iPhone check

Build and run Findly, open it once to refresh the sharing catalog, then share a file from WhatsApp. Confirm the preview, title, Add Tag sheet, tag selection/creation/removal, Add notes, bottom Save button, and automatic return after Saved. Reopen Findly and check the file and metadata. Also cancel a share after opening the picker and verify no item was saved.

## Plain-text sharing

The activation rule also accepts `public.plain-text` and conforming types. The loader converts a shared string into a UTF-8 `.txt` note, preserving the entire message; a bounded 2,000-character excerpt occupies the same preview area, and the first line suggests the title. File attachments retain their existing path. This requires reinstalling the updated build so iOS sees the changed activation rule.

Validation: 85-test full suite passed, followed by the five presentation tests including the new shared-message render. The installed extension predicate was evaluated against plain text, UTF-8 text, PDF, image, URL, and multiple-attachment inputs. Text tests cover emoji, Telugu, whitespace, embedded links, long messages, empty messages, and complete import into the vault. The shared-message render was visually inspected. The WhatsApp-to-Findly flow on a physical iPhone still needs confirmation with this build.
