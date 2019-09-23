
## 前言
Leanback库是google出的专注于Android TV开发的库，作为TV开发有必要对它的源码有一定的了解


## ObjectAdapter

#### DataObserver

当ObjectAdapter中的数据发生变化时，DataObserver作为观察者,会对这些变化做出相应，对应的是调用adapter的notify方法。

#### DataObservable
 既然有观察者当然就有被观察者，当ObjectAdapter的数据发生变化时，被观察者会提醒所有注册的观察者做出相应的变化，这个就是典型
 的观察者模式。


#### setPresenterSelector
设置PresenterSelector，PresenterSelector中包含了所有了Presenter，关于这两者的概念，之后我们会涉及到。


## Presenter

Presenter的作用是是关联RecyclerView中的itemView和数据实体，他和RecyclerView中的Adapter概念相近，但是Presenter是不基于
position的
