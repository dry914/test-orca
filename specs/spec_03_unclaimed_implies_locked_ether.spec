# Pillar 3 — State implication without enumeration.
#
# If any finalized-but-unclaimed request exists, the queue's locked ether
# must be positive. The free variable `reqId` lets the SMT solver hunt for
# a violating valuation directly: solver finds the witness, no manual scan.
#
# Solvency-adjacent property: a violation would mean either `lockedEther`
# was decremented incorrectly during claim, or `finalize` raised the
# frontier without locking ether — both real bug classes.
#
# Foundry equivalent: scan the queue every check to determine whether any
# claimable request exists, then assert. Gas-bounded queue depth in tests,
# and the assertion is structurally awkward — existence-check followed by
# a global property — in a language designed for unit tests.

vars: WithdrawalQueueERC721 wq, uint256 reqId

inv: (reqId > 0
      && reqId <= wq.getLastFinalizedRequestId()
      && !wq.queue(reqId)[5])
     ==> wq.getLockedEtherAmount() > 0
