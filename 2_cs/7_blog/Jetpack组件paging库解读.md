

## 简述
paging是jetpack中一个处理分页的组件，它和RecyclerView有着很好的兼容性，但是在做TV开发使用Leanback的时候，
遇到了一些问题，那就是paging中使用的adapter是RecyclerView的adapter,但是leanback中使用的adapter则不是
RecyclerView中的adapter,所以需要对paging的源码做一定的修改，既然要修改，就需要对paging有个深入的了解。
下面就深入paging的源码看看。


## PagedListAdapter

他是paging中提供的adapter，继承的是RecyclerView的adapter.但是他里面的逻辑主要是交给AsyncPagedListDiffer
类去处理了。在创建PagedListAdapter的时候，需要传入一个DiffUtil.ItemCallback，这个参数的作用是提供RecyclerView
中对新旧数据进行diff计算的条件。


```
public abstract class PagedListAdapter<T, VH extends RecyclerView.ViewHolder>
        extends RecyclerView.Adapter<VH> {
    private final AsyncPagedListDiffer<T> mDiffer;
    private final AsyncPagedListDiffer.PagedListListener<T> mListener =
            new AsyncPagedListDiffer.PagedListListener<T>() {
        @Override
        public void onCurrentListChanged(@Nullable PagedList<T> currentList) {
            PagedListAdapter.this.onCurrentListChanged(currentList);
        }
    };

    /**
     * Creates a PagedListAdapter with default threading and
     * {@link android.support.v7.util.ListUpdateCallback}.
     *
     * Convenience for {@link #PagedListAdapter(AsyncDifferConfig)}, which uses default threading
     * behavior.
     *
     * @param diffCallback The {@link DiffUtil.ItemCallback DiffUtil.ItemCallback} instance to
     *                     compare items in the list.
     */
    protected PagedListAdapter(@NonNull DiffUtil.ItemCallback<T> diffCallback) {
        mDiffer = new AsyncPagedListDiffer<>(this, diffCallback);
        mDiffer.mListener = mListener;
    }

    @SuppressWarnings("unused, WeakerAccess")
    protected PagedListAdapter(@NonNull AsyncDifferConfig<T> config) {
        mDiffer = new AsyncPagedListDiffer<>(new AdapterListUpdateCallback(this), config);
        mDiffer.mListener = mListener;
    }

    /**
     * Set the new list to be displayed.
     * <p>
     * If a list is already being displayed, a diff will be computed on a background thread, which
     * will dispatch Adapter.notifyItem events on the main thread.
     *
     * @param pagedList The new list to be displayed.
     */
    public void submitList(PagedList<T> pagedList) {
        mDiffer.submitList(pagedList);
    }

    @Nullable
    protected T getItem(int position) {
        return mDiffer.getItem(position);
    }

    @Override
    public int getItemCount() {
        return mDiffer.getItemCount();
    }

    /**
     * Returns the PagedList currently being displayed by the Adapter.
     * <p>
     * This is not necessarily the most recent list passed to {@link #submitList(PagedList)},
     * because a diff is computed asynchronously between the new list and the current list before
     * updating the currentList value. May be null if no PagedList is being presented.
     *
     * @return The list currently being displayed.
     */
    @Nullable
    public PagedList<T> getCurrentList() {
        return mDiffer.getCurrentList();
    }

    /**
     * Called when the current PagedList is updated.
     * <p>
     * This may be dispatched as part of {@link #submitList(PagedList)} if a background diff isn't
     * needed (such as when the first list is passed, or the list is cleared). In either case,
     * PagedListAdapter will simply call
     * {@link #notifyItemRangeInserted(int, int) notifyItemRangeInserted/Removed(0, mPreviousSize)}.
     * <p>
     * This method will <em>not</em>be called when the Adapter switches from presenting a PagedList
     * to a snapshot version of the PagedList during a diff. This means you cannot observe each
     * PagedList via this method.
     *
     * @param currentList new PagedList being displayed, may be null.
     */
    @SuppressWarnings("WeakerAccess")
    public void onCurrentListChanged(@Nullable PagedList<T> currentList) {
    }
}


```
