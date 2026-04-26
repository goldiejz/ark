# Ark — Roadmap

## Phase 0 — Bootstrap (complete)
- [x] Vault structure
- [x] 24 CLI commands
- [x] Brain → Ark rename
- [x] Verification suite
- [x] Observer daemon

## Phase 1 — GSD Integration (current)
- [ ] Audit all Ark scripts for GSD-shape assumptions
- [ ] Decide: delegate to /gsd commands vs reimplement
- [ ] Implement GSD-aware phase resolution end-to-end
- [ ] Add test coverage for GSD layouts
- [ ] Update ark verify to test GSD compatibility
- [ ] Document GSD/Ark relationship

## Phase 2 — Real-World Production Run
- [ ] Set up Cloudflare credentials for first real deploy
- [ ] Run ark deliver --phase 1.5 on strategix-servicedesk end-to-end
- [ ] First production promote with --confirm
- [ ] Capture lessons from real run

## Phase 3 — Multi-Stack Validation
- [ ] Test ark create for FastAPI, Django, Rust, Go stacks
- [ ] Verify deploy targets: vercel, fly, aws-ecs

## Phase 4 — Hardening
- [ ] Stress-test Phase 6 daemon under load
- [ ] Multi-machine vault sync verification
- [ ] Disaster recovery drill

## Phase 5 — Stakeholder & Reporting
- [ ] Investor/customer report templates
- [ ] Cross-project portfolio analytics
