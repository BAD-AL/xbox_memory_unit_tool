# SuperPowers: Agentic Engineering Guidelines


This document establishes standard operating procedures for AI agents to ensure high-signal development, architectural integrity, and systematic reliability across any software project.


## 1. The Pre-Flight Mandate (Think Before Code)


### 1.1 Socratic Brainstorming
- **Directive:** Before implementation, the agent MUST ask clarifying questions to explore edge cases, dependency conflicts, and user intent.
- **Requirement:** At least 3 high-signal questions must be answered by the user before major code changes occur.


### 1.2 Multi-Phase Planning
- **Directive:** Every request must be broken down into a numbered **Plan -> Act -> Verify** cycle.
- **Granularity:** Tasks should be segmented into 5-10 minute work intervals. The agent must provide status updates between phases.


## 2. Technical Rigor (Stability Standards)


### 2.1 Test-Driven Development (TDD)
- **Directive:** Complex logic, parsers, or mathematical algorithms MUST be verified via a standalone test script before integration into the main application.
- **Verification:** Integration is only permitted after the standalone test prints a successful result.


### 2.2 Systematic Debugging (4-Phase RCA)
When an error occurs, the agent MUST follow this Root Cause Analysis (RCA) flow:
1. **Identify:** Capture the raw stack trace and reproduce the failure state.
2. **Diagnose:** Execute diagnostic probes to verify environment variables, API responses, or file permissions.
3. **Defend:** Implement a fix that handles the immediate error AND adds a guardrail (e.g., input validation, error handling) to prevent recurrence.
4. **Verify:** Empirically prove the fix works using the diagnostic tools from Step 2.


## 3. Workspace Hygiene


### 3.1 Legacy Artifact Management
- **Directive:** Redundant or replaced files MUST NOT be deleted immediately.
- **Procedure:** Move artifacts to a `remove_this/` directory. Final deletion only occurs upon explicit user directive.


### 3.2 Documentation as Code
- **Directive:** Documentation must be updated in tandem with code changes.
- **Tracking:** Maintain a summary of environment changes (libraries, paths, versions) and high-level project requirements.


## 4. Operational Best Practices


- **Atomic Commits/Changes:** Prefer making small, functional updates rather than massive, sweeping refactors.
- **Safe I/O:** Always check for file existence and use try-except blocks for network or filesystem operations.
- **Decoupled Architecture:** Prioritize separation of concerns (e.g., separate data-fetching logic from UI/Display logic).

## 5. Create a Project Checklist (ProjectChecklist.md)
- Update this checklist as progress is made, add to it as needed.

---
*Status: Generic Framework Active*




