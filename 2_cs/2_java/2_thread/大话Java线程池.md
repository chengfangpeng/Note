## 场景再现

最近在开发中遇到个问题，为了问题的描述，我把它抽象成了一个榨汁机榨果汁的问题：有三种水果:苹果、橘子、桃子，一个榨汁机，要求：榨汁机每次只能榨一种水果，并且榨每种水果的机会要均等。另外如果同种类水果中有新鲜的水果运过来，则使用新鲜的水果榨汁，不新鲜的将被丢弃(不要在意这个奇葩问题，它只是个模型)。

## 解决问题

其实实现这个问题，应该有很多的方式，为了映衬我们的主题，我们采用线程池的方式解决。先分析一下问题，每一个水果其实可以看成是一个榨汁的任务，而我们只有一台榨汁机，那么说明这个任务只需要一个单的线程就可以执行。但是我们为了我们问题的简化，使用了java中提供的线程池。具体做法如下：

```

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "MainActivity";

    private LinkedBlockingQueue<Runnable> mBlockingQueue = new LinkedBlockingQueue<>();

    private ExecutorService mExecutorService = new ThreadPoolExecutor(1, 1, 0, TimeUnit.MICROSECONDS, mBlockingQueue);

    private Button btnAppleJuice, btnOrangeJuice, btnPeachJuice;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        btnAppleJuice = findViewById(R.id.btn_apple_juice);
        btnOrangeJuice = findViewById(R.id.btn_orange_juice);
        btnPeachJuice = findViewById(R.id.btn_peach_juice);
        btnAppleJuice.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                execute(new TypeRunnable(TypeRunnable.NAME_APPLE_JUICE) {

                    @Override
                    public void run() {
                        super.run();
                        try {
                            Thread.sleep(10000);
                            Log.d(TAG, "榨苹果汁...");
                        } catch (InterruptedException e) {
                            e.printStackTrace();
                        }
                    }
                });

            }
        });
        btnOrangeJuice.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                execute(new TypeRunnable(TypeRunnable.NAME_ORANGE_JUICE) {

                    @Override
                    public void run() {
                        super.run();
                        try {
                            Thread.sleep(10000);
                            Log.d(TAG, "榨橘子汁...");
                        } catch (InterruptedException e) {
                            e.printStackTrace();
                        }
                    }
                });
            }
        });

        btnPeachJuice.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                execute(new TypeRunnable(TypeRunnable.NAME_PEACH_JUICE) {

                    @Override
                    public void run() {
                        super.run();
                        try {
                            Thread.sleep(10000);
                            Log.d(TAG, "榨桃汁...");
                        } catch (InterruptedException e) {
                            e.printStackTrace();
                        }
                    }
                });
            }
        });
    }

    /**
     * 执行任务
     *
     * @param runnable
     */
    private void execute(TypeRunnable runnable) {

        Log.d(TAG, "queue size = " + mBlockingQueue.size());
        Log.d(TAG, "execute, name is = " + runnable.getName());
        Iterator<Runnable> element = mBlockingQueue.iterator();
        while (element.hasNext()) {
            Runnable r = element.next();
            if (r instanceof TypeRunnable && ((TypeRunnable) r).getName() == runnable.getName()) {
                Log.d(TAG, "TypeRunnable remove, Name is = " + runnable.getName());
                element.remove();
            }
        }
        mExecutorService.execute(runnable);
    }


}



```
代码中使用了java中的线程池ThreadPoolExecutor和队列LinkedBlockingQueue，他们是如何使用的，又如何扩展，介绍完这些内容再看上面的代码就一目了然了。
