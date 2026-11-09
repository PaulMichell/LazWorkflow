package computing.michell.monitor.ui

/* Selection-aware XML prompt editor (c) 2026 Michell Computing. */

import android.content.Context
import android.util.AttributeSet
import android.widget.EditText

class PromptEditText @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : EditText(context, attrs) {
  var onSelection: ((Int, Int) -> Unit)? = null

  override fun onSelectionChanged(start: Int, end: Int) {
    super.onSelectionChanged(start, end)
    onSelection?.invoke(start, end)
  }
}
