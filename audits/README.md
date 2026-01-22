## Audit Reports

### Nethermind AuditAgent (2026-01-21)

- **Report**: `audits/raw/audit_agent_report_1_d530a46b-4d72-43b4-b64b-0db3bffb285c.pdf`
- **Alias (recommended)**: `audits/2026-01-21-nethermind-auditagent.pdf`
- **Tool**: Nethermind AuditAgent (PDF report attached)
- **Score**: 99/100
- **Scope**:
  - Cairo contracts: `src/contracts/*`, `src/crypto/*`, `src/interfaces/*`
  - SDK + scripts (read-only review)

#### Findings Summary

| # | Finding | Severity | Status | Notes / Evidence |
|---|---------|----------|--------|------------------|
| 1 | Announcement stream can be spammed; per-caller rate limiting is sybil-bypassable | Low | **Accepted** | Permissionless announce is a documented trade-off; rate limits are per-caller |
| 2 | Factory `compute_stealth_address` missing address normalization | Low | **Fixed** | Added normalization to contract address domain; unit + fuzz tests added |
| 3 | Registry owner set from fee-paying account in constructor | Info | **Fixed** | Constructor now takes explicit `owner` (non-zero) |
| 4 | No upgrade mechanisms for core contracts | Info | **Accepted** | Intentional immutability; documented in SNIP/README |
| 5 | Docs vs. admin controls / rate limiting mismatch | Info | **Fixed** | Default gap = 0, capped max, non-retroactive updates; docs updated |
| 6 | Ownership transfer can be initiated to zero address | Best practice | **Fixed** | Reject zero owner in transfer |
| 7 | No cancel ownership transfer | Best practice | **Fixed** | Added `cancel_ownership_transfer` |
| 8 | `ClassHashUpdated` event unused in factory | Best practice | **Fixed** | Removed dead event |

#### Remediation Notes

- **Registry owner explicit**: `constructor(owner)` + zero check.
- **Rate limiting**: default disabled, max cap, non-retroactive semantics, new test.
- **Address normalization**: normalize final hash into contract address domain.
- **Ownership UX**: zero-address prevention + cancel transfer.
- **Factory cleanup**: removed unused event.

#### Accepted Trade-offs

- Permissionless `announce` can be spammed; per-caller limits are sybil-bypassable.
- Contracts are intentionally immutable; upgrades require redeploy/migration.

#### Commit References

Remediations listed above are **applied and committed** in the repository.
This summary reflects the current contract code and deployments in
`deployments/sepolia.json`.
