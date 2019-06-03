

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

## AsyncPagedListDiffer
上面已经提到了PagedListAdapter中的主要逻辑都是AsyncPagedListDiffer来完成的，那么我们看看AsyncPagedListDiffer
的代码。




```

public class AsyncPagedListDiffer<T> {
    // updateCallback notifications must only be notified *after* new data and item count are stored
    // this ensures Adapter#notifyItemRangeInserted etc are accessing the new data
    private final ListUpdateCallback mUpdateCallback;
    private final AsyncDifferConfig<T> mConfig;

    @SuppressWarnings("RestrictedApi")
    Executor mMainThreadExecutor = ArchTaskExecutor.getMainThreadExecutor();

    // TODO: REAL API
    interface PagedListListener<T> {
        void onCurrentListChanged(@Nullable PagedList<T> currentList);
    }

    @Nullable
    PagedListListener<T> mListener;

    private boolean mIsContiguous;

    private PagedList<T> mPagedList;
    private PagedList<T> mSnapshot;

    // Max generation of currently scheduled runnable
    private int mMaxScheduledGeneration;

    /**
     * Convenience for {@code AsyncPagedListDiffer(new AdapterListUpdateCallback(adapter),
     * new AsyncDifferConfig.Builder<T>(diffCallback).build();}
     *
     * @param adapter Adapter that will receive update signals.
     * @param diffCallback The {@link DiffUtil.ItemCallback DiffUtil.ItemCallback} instance to
     * compare items in the list.
     */
    @SuppressWarnings("WeakerAccess")
    public AsyncPagedListDiffer(@NonNull RecyclerView.Adapter adapter,
            @NonNull DiffUtil.ItemCallback<T> diffCallback) {
        mUpdateCallback = new AdapterListUpdateCallback(adapter);
        mConfig = new AsyncDifferConfig.Builder<T>(diffCallback).build();
    }

    @SuppressWarnings("WeakerAccess")
    public AsyncPagedListDiffer(@NonNull ListUpdateCallback listUpdateCallback,
            @NonNull AsyncDifferConfig<T> config) {
        mUpdateCallback = listUpdateCallback;
        mConfig = config;
    }

    private PagedList.Callback mPagedListCallback = new PagedList.Callback() {
        @Override
        public void onInserted(int position, int count) {
            mUpdateCallback.onInserted(position, count);
        }

        @Override
        public void onRemoved(int position, int count) {
            mUpdateCallback.onRemoved(position, count);
        }

        @Override
        public void onChanged(int position, int count) {
            // NOTE: pass a null payload to convey null -> item
            mUpdateCallback.onChanged(position, count, null);
        }
    };

    /**
     * Get the item from the current PagedList at the specified index.
     * <p>
     * Note that this operates on both loaded items and null padding within the PagedList.
     *
     * @param index Index of item to get, must be >= 0, and &lt; {@link #getItemCount()}.
     * @return The item, or null, if a null placeholder is at the specified position.
     */
    @SuppressWarnings("WeakerAccess")
    @Nullable
    public T getItem(int index) {
        if (mPagedList == null) {
            if (mSnapshot == null) {
                throw new IndexOutOfBoundsException(
                        "Item count is zero, getItem() call is invalid");
            } else {
                return mSnapshot.get(index);
            }
        }
        //这里出发PagedList去加载新的数据
        mPagedList.loadAround(index);
        return mPagedList.get(index);
    }

    /**
     * Get the number of items currently presented by this Differ. This value can be directly
     * returned to {@link RecyclerView.Adapter#getItemCount()}.
     *
     * @return Number of items being presented.
     */
    @SuppressWarnings("WeakerAccess")
    public int getItemCount() {
        if (mPagedList != null) {
            return mPagedList.size();
        }

        return mSnapshot == null ? 0 : mSnapshot.size();
    }

    /**
     * Pass a new PagedList to the differ.
     * <p>
     * If a PagedList is already present, a diff will be computed asynchronously on a background
     * thread. When the diff is computed, it will be applied (dispatched to the
     * {@link ListUpdateCallback}), and the new PagedList will be swapped in as the
     * {@link #getCurrentList() current list}.
     *
     * @param pagedList The new PagedList.
     */
    public void submitList(final PagedList<T> pagedList) {
        if (pagedList != null) {
            if (mPagedList == null && mSnapshot == null) {
                mIsContiguous = pagedList.isContiguous();
            } else {
                if (pagedList.isContiguous() != mIsContiguous) {
                    throw new IllegalArgumentException("AsyncPagedListDiffer cannot handle both"
                            + " contiguous and non-contiguous lists.");
                }
            }
        }

        if (pagedList == mPagedList) {
            // nothing to do
            return;
        }

        // incrementing generation means any currently-running diffs are discarded when they finish
        final int runGeneration = ++mMaxScheduledGeneration;

        if (pagedList == null) {
            int removedCount = getItemCount();
            if (mPagedList != null) {
                mPagedList.removeWeakCallback(mPagedListCallback);
                mPagedList = null;
            } else if (mSnapshot != null) {
                mSnapshot = null;
            }
            // dispatch update callback after updating mPagedList/mSnapshot
            mUpdateCallback.onRemoved(0, removedCount);
            if (mListener != null) {
                mListener.onCurrentListChanged(null);
            }
            return;
        }

        if (mPagedList == null && mSnapshot == null) {
            // fast simple first insert
            mPagedList = pagedList;
            pagedList.addWeakCallback(null, mPagedListCallback);

            // dispatch update callback after updating mPagedList/mSnapshot
            mUpdateCallback.onInserted(0, pagedList.size());

            if (mListener != null) {
                mListener.onCurrentListChanged(pagedList);
            }
            return;
        }

        if (mPagedList != null) {
            // first update scheduled on this list, so capture mPages as a snapshot, removing
            // callbacks so we don't have resolve updates against a moving target
            mPagedList.removeWeakCallback(mPagedListCallback);
            mSnapshot = (PagedList<T>) mPagedList.snapshot();
            mPagedList = null;
        }

        if (mSnapshot == null || mPagedList != null) {
            throw new IllegalStateException("must be in snapshot state to diff");
        }

        final PagedList<T> oldSnapshot = mSnapshot;
        final PagedList<T> newSnapshot = (PagedList<T>) pagedList.snapshot();
        mConfig.getBackgroundThreadExecutor().execute(new Runnable() {
            @Override
            public void run() {
                final DiffUtil.DiffResult result;
                result = PagedStorageDiffHelper.computeDiff(
                        oldSnapshot.mStorage,
                        newSnapshot.mStorage,
                        mConfig.getDiffCallback());

                mMainThreadExecutor.execute(new Runnable() {
                    @Override
                    public void run() {
                        if (mMaxScheduledGeneration == runGeneration) {
                            latchPagedList(pagedList, newSnapshot, result);
                        }
                    }
                });
            }
        });
    }

    private void latchPagedList(
            PagedList<T> newList, PagedList<T> diffSnapshot,
            DiffUtil.DiffResult diffResult) {
        if (mSnapshot == null || mPagedList != null) {
            throw new IllegalStateException("must be in snapshot state to apply diff");
        }

        PagedList<T> previousSnapshot = mSnapshot;
        mPagedList = newList;
        mSnapshot = null;

        // dispatch update callback after updating mPagedList/mSnapshot
        PagedStorageDiffHelper.dispatchDiff(mUpdateCallback,
                previousSnapshot.mStorage, newList.mStorage, diffResult);

        newList.addWeakCallback(diffSnapshot, mPagedListCallback);
        if (mListener != null) {
            mListener.onCurrentListChanged(mPagedList);
        }
    }

    /**
     * Returns the PagedList currently being displayed by the differ.
     * <p>
     * This is not necessarily the most recent list passed to {@link #submitList(PagedList)},
     * because a diff is computed asynchronously between the new list and the current list before
     * updating the currentList value. May be null if no PagedList is being presented.
     *
     * @return The list currently being displayed, may be null.
     */
    @SuppressWarnings("WeakerAccess")
    @Nullable
    public PagedList<T> getCurrentList() {
        if (mSnapshot != null) {
            return mSnapshot;
        }
        return mPagedList;
    }
}


```
