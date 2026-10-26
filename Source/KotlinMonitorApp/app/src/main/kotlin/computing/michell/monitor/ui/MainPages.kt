package computing.michell.monitor.ui

/* Page order for the main conversation and plan swipe (c) 2026 Michell Computing.

   A horizontal swipe advances in this order. In left-to-right layout, moving
   the finger toward the leading edge opens Plan; the reverse returns to
   Conversation. The bottom bar uses the same order. */

val MainTabs = listOf(AppTab.Conversation, AppTab.Plan)

fun pageForTab(tab: AppTab): Int {
  val index = MainTabs.indexOf(tab)
  if (index >= 0) return index
  return 0
}

fun tabForPage(page: Int): AppTab {
  if (page < 0 || page >= MainTabs.size) return AppTab.Conversation
  return MainTabs[page]
}

fun tabCaption(tab: AppTab): String {
  return when (tab) {
    AppTab.Conversation -> "Conversation"
    AppTab.Plan -> "Plan"
  }
}

/** Tab to apply when a swipe settles. Null when that page is already selected. */
fun tabAfterSwipe(settledPage: Int, current: AppTab): AppTab? {
  val next = tabForPage(settledPage)
  if (next == current) return null
  return next
}


