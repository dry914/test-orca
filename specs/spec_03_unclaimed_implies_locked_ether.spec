# Pillar 3 — State implication without enumeration (free variable form).
#
# Strict version (testing [V] array-literal support):
#   If any finalized-but-unclaimed request exists, locked ether must be positive.
#
# Encoding:
#   - `wq.getLastFinalizedRequestId()` — scalar uint256 view, used in PR-1570 form.
#   - `wq.getWithdrawalStatus(uint256[])` — public getter returning
#       WithdrawalRequestStatus[]. Per-id status fields (index inside struct):
#         [0] amountOfStETH, [1] amountOfShares, [2] owner,
#         [3] timestamp,    [4] isFinalized,    [5] isClaimed
#     We pass `[reqId]` as an array literal of length 1 and read field [5]
#     from element [0]: `wq.getWithdrawalStatus([reqId])[0][5]`.
#
# This run is a *parser probe*: we want to learn whether [V] accepts the
# `[reqId]` array-literal argument syntax + double indexing on the returned
# struct-array. If it parses and the spec evaluates, we keep the strict form;
# if it fails, we fall back to the helper-view (`WQView.isClaimed`) workaround.

vars: WithdrawalQueueERC721 wq, uint256 reqId

inv: (reqId > 0
      && reqId <= wq.getLastFinalizedRequestId()
      && !wq.getWithdrawalStatus([reqId])[0][5])
     ==> wq.getLockedEtherAmount() > 0
