# Evidence-first troubleshooting

Do not ask the tablet operator to retype long diagnostic command sequences.
Use `tb321fu-support-bundle`, preserve the resulting archive unchanged, and
attach its SHA-256 to a hardware issue or experiment record.

## Failure handling

1. Assign one experiment ID and one primary question.
2. Record commit, workflow run, profile, image hashes, and whether the device
   is currently Kubuntu or an Arch candidate.
3. Collect the support bundle before rebooting when possible.
4. Record the exact observed result and recovery action as PASS, FAIL, or NOT
   TESTED. Never rewrite a failed entry into a pass.
5. A retry must cite the old experiment and identify new evidence or the one
   changed variable. Otherwise stop.

## Source-versus-hardware boundary

- Source tests can prove syntax, retry logic, timeouts, redaction fixtures,
  and deterministic file placement.
- They cannot prove Type-C role switching, UDC creation, NAP advertisement,
  Wi-Fi firmware operation, display timing, touch mapping, audio, charging, or
  suspend behavior on TB321FU.

If identity, GPT, image hashes, rescue availability, or log preservation is
unclear, stop instead of switching tools or repeating a destructive step.
