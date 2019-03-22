## performFocusNavigation -> mView.findFocus()
需找当前页面的焦点，如果是view,判断是否获取焦点，如果获取直接返回当前view,如果未获取焦点返回null. 如果mView是ViewGroup，则遍历自己的子View，如果找不到返回null

## focused.focusSearch(direction)

不是根布局一步一步往父布局找，除非中间中view或者ViewGroup复写了该方法返回一个确定的View,
最终找到父ViewGroup的

```
@Override
    public View focusSearch(View focused, int direction) {
        if (isRootNamespace()) {
            // root namespace means we should consider ourselves the top of the
            // tree for focus searching; otherwise we could be focus searching
            // into other tabs.  see LocalActivityManager and TabHost for more info.
            return FocusFinder.getInstance().findNextFocus(this, focused, direction);
        } else if (mParent != null) {
            return mParent.focusSearch(focused, direction);
        }
        return null;
    }

```
如果已经是根布局，调用FocusFinder.getInstance().findNextFocus(this, focused, direction)

## requestFocus()
在focused.focusSearch()之后，新获取到焦点的view会调用requestFocus()
-> View#requestFocusNoSearch() -> handleFocusGainInternal()
如果有父view会调用父view的requestChildFocus()之后也会调用view的onFocusChanged()方法和refreshDrawableState(),同时父View如果还有父布局还会继续调用父布局的requestChildFocus，这样一层一层的往上调用。
