> この記事は、2017/09/15〜17 に早稲田大学 理工学部 西早稲田キャンパスで開催される **iOSDC Japan 2017** で行われる**[セッション「RxSwiftのObservableとは何か」](https://iosdc.jp/2017/node/1348)**の発表原稿、およびその補足資料です。

* スライドはこちらです ➡︎ https://www.slideshare.net/gomi_ningen/rxswiftobservable-iosdc-japan-2017
* あわせて読みたい ➡︎ http://qiita.com/gomi_ningen/items/dc08a8a5514be9aa0eb2


なお、本文に先立ち注意事項を掲載しておきます。

**注意事項**

* 以下の内容を理解しなくても RxSwift は十分使えるライブラリです
  * まだ Rx 系のライブラリを使ったことがない方は、まずライブラリを使ってみてください
  * Qiitaの記事を読むのもよいですが、**[公式のドキュメント](https://github.com/ReactiveX/RxSwift)や[Example](https://github.com/ReactiveX/RxSwift/blob/master/Documentation/Examples.md)**が充実しているのでそちらを読みながら、**まずはコードを書いてみることを強くお勧めします。**意外に簡単に使いどころが理解できるようになると思います。
* 記事の内容的には Rx 系ライブラリの利用経験がなくても分かるように書いたつもりです
* 以下の実装は RxSwift のものであり、他言語の Rx ライブラリとは実装が異なる場合があります


# 1.RxSwiftとは？

　**ReactiveExtensions(Rx)** とは一体何をするライブラリなのでしょうか？ [ReactiveX](http://reactivex.io/) のWebページ冒頭や [RxSwiftの README](https://github.com/ReactiveX/RxSwift/blob/master/README.md) にはこのように書かれています

> * An API for asynchronous programming with observable streams.（Observable を用いた非同期プログラミングのためのAPI）
> * Rx is a generic abstraction of computation expressed through Observable<Element> interface. （Rxは Observable<Element> を用いて計算を抽象化します）

　どちらにも `Observable` というキーワードが登場しています。このことから、Rx を理解するためには、`Observable` について理解する必要がありそうだということがお分りいただけるかと思います。

実際に Rx は、主に以下の3つの要素から構成されていると言ってよいでしょう。

1. **Observable** (`Observable`, `Observer`, `Disposable`, etc...)
2. **Operator** (`map`, `flatMap`, `filter`, etc...)
3. **Scheduler** (`MainScheduler`, `ConcurrentDispatchQueueScheduler`, etc...)

　本セッションでは、このうち `Observable` にスポットライトをあて、その実装を俯瞰していくことによって Rx への理解を深めることを目的としてお話を進めていきます。

　しばしば、Rx のストリームは「川である」といったように様々なものの例えで表現されることがあります。またリアクティブプログラミングとは〜のようなものであるといった記事がネット上にはたくさん存在します。こうした、あいまいでつかみどころのない例え話や解説記事から一歩足を踏み入れて、コードレベルで振る舞いを理解することにチャレンジしてみませんか。

　実装を知ることは、 RxSwift をはじめとした Rx 系ライブラリを活用する手助けになるだけでなく、ソフトウェアを設計する上でのひとつの大きな指針を手にいれることにも繋がると、私は考えています。


# 2. Observerパターンとそのバリエーション
## 2.1. Observer パターンの問題意識

　Rx の `Observable` の実装を見ていく前に、ひとつの問題について考えてみましょう。

> **Q1. 「A に変化が生じたら B に伝えたい」とき、どうすればよいでしょうか？** 

現実世界に置き換えると、以下のように例えられると思います。

* 【例1】 自分の予定が変わったので（状態変化）、お店に予約キャンセルの連絡をする（通知）
* 【例2】 従業員は体調が悪くなったので（状態変化）、上司に会社を休む連絡をする（通知）

　実際にこのようなケースの場合、自分が相手の連絡先を保持して、連絡をとる（相手に通知する）ことになるかと思います。【例2】のケースを考えると、普通従業員は上司の連絡先をあらかじめ保持していて、適切なタイミングでお休みの連絡を入れるのではないでしょうか。これはプログラミングの世界でも一緒で、「A に変化が生じたら B に伝えたい」ときには、「A が B の参照を保持しておき、状態変化時に通知する」という構造になります。

![](https://qiita-image-store.s3.amazonaws.com/0/56771/21afb2a6-e49a-3e99-3514-47d4c21875d9.png)

　【例2】のパターンをコードで表現すると以下のようになると思います。Playgroudで動作するコードですのでお試しください。

```swift:Notify.swift
class Member {
    private let boss: Boss
    public var isFine: Bool = true {
        didSet(value) { boss.notify() }
    }
    
    public init(boss: Boss) { self.boss = boss }
}

class Boss {
    public func notify() {
        NSLog("誰かから通知が来たよ")
    }
}

var boss1 = Boss()
var member1 = Member(boss: boss1)
member1.isFine = true  //=> ログ出力される
member1.isFine = false //=> ログ出力される
```

　この実装は、問題を解決できており、完全に正しい実装です。与えられた前提条件に対して設計上の問題点はありません。さて、これを踏まえて考える問題をもう少し複雑にしてみましょう。

> **Q2. 「通知元（A）の状態変化を、複数の通知先（B, C, D...）に伝えたい」とき、どうすればよいでしょうか？** 

　基本的に A が B, C, D の参照を保持するという点については変わりませんが、B, C, D に通知をする際のインターフェースが同じであるとは限りません。これは現実に例えば、友人数人と遊ぶ約束をしていて、遅刻しそうなとき、B さんは twitter、C さんは 電話、D さんはメールで連絡しなければいけないといったような状況です。

![](https://qiita-image-store.s3.amazonaws.com/0/56771/8f63fb00-bba6-4995-40f1-70304e025800.png)

```swift:Notify2.swift
class A {
    private let b: B
    private let c: C
    private let d: D
    public var isFine: Bool = true {
        didSet(value) {
            if value {
                b.notifyByTwitter()
                c.notifyByTelephone()
                d.notifyByEmail()
            }
        }
    }
    public init(b: B, c: C, d: D) {
        self.b = b; self.c = c; self.d = d;
    }
}

class B { func notifyByTwitter() { NSLog("連絡がきた") } }
class C { func notifyByTelephone() { NSLog("連絡がきた") } }
class D { func notifyByEmail() { NSLog("連絡がきた") } }
```

## 2.2. pull 型 Observer パターン

先にみた構造には、以下のような問題点があります。

1. 通知先のオブジェクトが変更されたとき、通知元の実装も変更しなければならない
2. 通知先のオブジェクトの種類が増えるとき、通知元の実装も追加しなければならない

　2つの問題は通知元のオブジェクトが、通知先のオブジェクトの詳細を知りすぎているということに起因しています。通知元は、通知先の参照をどうあがいても保持する必要がありますが、通知先の詳細を知ったまま保持する必要性はありません。

　つまり、通知元は、通知先の状態遷移を伝えるためのインターフェースだけを知っていればよいことになります。友人一般を表す `Friend` という名前で protocol を切り、通知を受け入れるメソッド `notify` を定義しておくと、B, C, D はそれぞれ下図のような構造にできるでしょう。

![](https://qiita-image-store.s3.amazonaws.com/0/56771/f1c331b0-1894-f0ac-7506-77e5d5ad1334.png)

　この形にすることにより、通知元の A のほうも 友人への参照を個別の型で保持するのではなく、`[Friend]` という配列で保持することができるようになりました。配列で保持しているので `Friend` プロトコルを実装した新たなインスタンスを容易に受け入れることができる構造となりました。また配列から要素の削除も容易に行えるため、通知を取りやめることも実現できる構造になっています。

　A が新たな Friend のインスタンスを受け入れるメソッドを `subscribe`、逆に取り除くメソッドを `unsubscribe` と命名すると以下の図のように単純に構造を表現できます

![](https://qiita-image-store.s3.amazonaws.com/0/56771/46f96f53-b81c-1974-af93-0e48b157d22f.png)

　ここまでの検討をまとめれば「通知元の状態変化を、複数の通知先に伝えたい」場合に、通知元と通知先が持っていてほしいインターフェース仕様が導けるでしょう。それぞれ次のようになります。

* 通知元（Observable=観測可能なオブジェクト）は次の2つのメソッドを持っていてほしい
  * 通知先（Observer=観測者）への通知を開始するためのメソッド（subscribe）
  * 通知先（Observer=観測者）への通知を終了するためのメソッド（unsubscribe）
* 通知先（Obseerver=観測者）は次の1つのメソッドを持っていてほしい
  * 通知を受け付けるメソッド（notify）

クラス図にまとめると以下のような形になります。

![](https://qiita-image-store.s3.amazonaws.com/0/56771/87114528-4843-fdbc-c0c5-3f8ea4bb47c8.png)

この構造は、**pull型 Observer パターン[^1]**と呼ばれています。Swiftで表現すると、やや制約のあるコードですが以下のように表現できます。

[^1]: [Erich Gamma, Richard Helm, Ralph Johnson, John Vlissides (1994). Design Patterns: Elements of Reusable Object-Oriented Software.]()

```swift:PullObserver.swift
public protocol Observable {
    func subscribe(obs: Observer)
    func unsubscribe(obs: Observer)
}

public class ConcreteObservable {
    private var observers: [Observer] = []
    public var isHoge: Bool = false {
        didSet { observers.forEach { x in x.notify() } }
    }
    public func subscribe(obs: Observer) { observers += [obs] }
    pubilc func unsubscribe(obs: Observer) {
        observers = observers.filter { x in
            // this means reference equality
            ObjectIdentifier(x) != ObjectIdentifier(obs)
        }
    }
}

public protocol Observer: class {
    func notify()
}

public class ConcreteObserver: Observer {
    public func notify() { NSLog("通知を受けた") }
}

// 以下のように playground でお試しできます
let v1 = ConcreteObservable()
let obs1 = ConcreteObserver()
v1.subscribe(obs: obs1)
v1.isHoge = false //=> ログ出力される
v1.isHoge = true  //=> ログ出力される
v1.unsubscribe(obs: obs1)
v1.isHoge = false //=> ログ出力されない
```

　C# で表現すると以下のようなコードになります。C#を読んだことがない方でも、言語の違いを飛び越えてほぼ同じような表現が可能であることがわかるのではないでしょうか。

```csharp:PullObserver.cs
namespace DotNetObservable
{
    public interface IObservable
    {
        void Subscribe(IObserver obs);
        void Unsubscribe(IObserver obs);
    }

    public class ConcreteObservable : IObservable
    {
        readonly IList<IObserver> observers = new List<IObserver>();
        bool isHoge;
        bool IsHoge
        {
            get => isHoge;
            set
            {
                isHoge = value;
                foreach (var obs in observers) obs.Notify();
            }
        }

        public void Subscribe(IObserver obs) => observers.Add(obs);
        public void Unsubscribe(IObserver obs) => observers.Remove(obs);
    }

    public interface IObserver
    {
        void Notify();
    }

    public class ConcreteObserver : IObserver
    {
        public void Notify() => Console.WriteLine("通知された");
    }
}
```

### pull 型 Observer パターンについてのまとめ

やや長くなったので、ここで pull 型 Observer パターンについてまとめておきましょう。pull 型Observerパターンは、「複数の異なる通知先に状態変化を通知したい」という問題の解決策として以下のような構造や特徴を持ちます。

1. 通知元（Observable）は、通知先（Observer）に共通したプロトコルを持つインスタンスをコレクションとして持ち、状態遷移時にそれぞれに通知する
2. `Observer` は、 `Observable` からなんらかの変化が発生したという情報だけを `notify()` メソッド経由で受け取れる
3. `Observer` は、必要に応じて `Observable` の値を問い合わせる（このあたりが pull 型と呼ばれる所以）


## 2.3. push 型 Observer パターン

　pull 型の Observer パターンを用いた場合、`Observer` は `Observable` の状態が更新されたという事実を知ることができますが、どのような値に更新されたのかは、 `Observable` のプロパティなどを参照しにいかなければ知ることができません。したがって、現実的には更新された値を参照するために、`Observer` も `Observable` の参照を何らかの方法で取得できる状況にする必要があり、相互参照する構造になってしまいます。

　この問題を解決するために、`notify` 時に更新後の値を渡してしまう構造にしたものが **push 型 Observer パターン** になります。構造は以下のようになります。

![](https://qiita-image-store.s3.amazonaws.com/0/56771/bf1b2f60-d206-f8ca-42d1-01be54b4f498.png)

　図中で interface が**型パラメータ（generic type parameter）**を持つ箇所がありますが、Swift の protocol は型パラメータを持てず、**関連型（associated type, abstract type member）** しかもてない仕様があり[^2]、この図をストレートにコードに落とし込むことができません。したがって、ひとまず C# で表現するならば以下のようなコードになります。

[^2]: https://developer.apple.com/library/content/documentation/Swift/Conceptual/Swift_Programming_Language/Generics.html

```csharp:PushObserver.cs
using System.Collections.Generic;

namespace DotNetObservable
{
    public interface IObservable<T>
    {
        void Subscribe(IObserver<T> obs);
        void Unsubscribe(IObserver<T> obs);
    }

    public class BooleanObservable : IObservable<bool>
    {
        readonly IList<IObserver<bool>> observers = new List<IObserver<bool>>();
        bool t;
        bool TValue
        {
            get => t;
            set
            {
                t = value;
                foreach (var obs in observers) obs.Notify(value);
            }
        }

        public void Subscribe(IObserver<bool> obs) => observers.Add(obs);
        public void Unsubscribe(IObserver<bool> obs) => observers.Remove(obs);
    }

    public interface IObserver<T>
    {
        void Notify(T t);
    }

    public class BooleanObserver : IObserver<bool>
    {
        public void Notify(bool t) => Console.WriteLine("通知された");
    }
}
```

Swift で表現するならば、ちょっと迂回して以下の図のような構造となるでしょう。

![](https://qiita-image-store.s3.amazonaws.com/0/56771/3d9fdd25-1b67-185e-3177-4ea8f37469a2.png)



　Swiftには抽象クラスというものは存在しませんが、擬似的に abstract method 内 で `fatalError()` を返すことを抽象クラスである印として、次のようにコードに落とし込めます。この技法は RxSwift のコード内部でも使われています[^3]。

[^3]: https://github.com/ReactiveX/RxSwift/blob/007af77912b39d84857a8e90eecdd02dd20164de/RxSwift/Rx.swift#L36

```swift:PushObserver.swift
public protocol ObserverType: class {
    associatedtype E
    func notify(value: E)
}

public protocol ObseravbleType {
    associatedtype E
    func subscribe<O: ObserverType>(obs: O) where O.E == E
    func unsubscribe<O: ObserverType>(obs: O) where O.E == E
}

public class Observable<Element>: ObseravbleType {
    public typealias E = Element
    public func subscribe<O: ObserverType>(obs: O) where O.E == E {
        fatalError("not implemented")
    }
    public func unsubscribe<O: ObserverType>(obs: O) where O.E == E {
        fatalError("not implemented")
    }
}

public class BooleanObservable: Observable<Bool> {
    private var observers: [ObjectIdentifier:AnonymousObserver<Bool>] = [:]
    public var isHoge: Bool = false { 
        didSet { observers.forEach { x in x.value.notify(value: isHoge) } }
    }
    public override func subscribe<O>(obs: O) where O : ObserverType, O.E == Bool {
        observers[ObjectIdentifier(obs)] = AnonymousObserver(handler: obs.notify)
    }
    
    public override func unsubscribe<O>(obs: O) where O : ObserverType, O.E == Bool {
        observers[ObjectIdentifier(obs)] = nil
    }
}

public class AnonymousObserver<Element>: ObserverType {
    public typealias E = Element
    public typealias Handler = (E) -> Void
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }
    public func notify(value: E) { handler(value) }
}

var observable = BooleanObservable()
var observer = AnonymousObserver<Bool>(handler: { x in NSLog(String(x)) })

observable.isHoge = false   //=> ログ出力されない
observable.subscribe(obs: observer)
observable.isHoge = true   //=> ログ出力される
observable.isHoge = false  //=> ログ出力される
observable.unsubscribe(obs: observer)
observable.isHoge = true   //=> ログ出力されない
```

　こうして、私たちは「通知元の状態変化を、複数の通知先に伝えたい」という問題を解決する実装パターンである **push 型 Observer パターン**を手にすることができました。 protocol が型パラメータを持てないという制約を回避するためにやや遠回りで苦しい実装をしましたが、構造的には C# のものと同じです。


# 3. RxSwift の Observer, Observable の実装

　さて、ここからはいよいよ RxSwift の `Observable` についてみていきます。基本的に push 型 Observer パターンと同じ構造になりますが、3つ異なる点があります。

1. notify 時に値を `.next`, `.error`, `.completed` という文脈につつむ enum `Event` にラップして渡している
2. `.next` 以外の値が飛んだ場合に、以後イベントは飛ばなくなる
3. `unsubscribe` の責務を `Disposable` に分離している

まずは前者から見ていきましょう。

![](https://qiita-image-store.s3.amazonaws.com/0/56771/ab659ff7-879b-de88-540d-6285e4009aa7.png)


## 3.1. Event の実装

　**RxSwift の `Observable` は変化した値(next)に加えて、エラー(error)と完了(completed)という文脈を `Observer` に通知することができます。**その文脈を表現するのが `Event` という enum です。実装が単純なので、コードをみたほうが理解がはやいでしょう。

```swift:Event.swift
public enum Event<Element> {
    case next(Element)
    case error(Error)
    case completed
}
```

また通知に関してもう一つだけ push 型　Observerパターンにはないルールがあります。それは **「`next` 以外の値が飛んだ場合に、以後イベントは飛ばなくなる」**というルールです。これは RxSwift のソースコード内で以下のように表現されています。

```swift:EventExtension.swift
extension Event {
    public var isStopEvent: Bool {
        switch self {
        case .next: return false
        case .error, .completed: return true
        }
    }
}
```


## 3.2. Disposable プロトコルの定義

　続いて `Disposable` プロトコルの定義についてみていきましょう。これも先に見た push 型の Observer パターンには存在しないものになります。このプロトコルは単純に**「push 型の Observer パターンの `unsubscribe` の役割をオブジェクトとして切り出した」**ものになります。したがって、`unsubscribe` を発火させる単純なメソッド `dispose` のみを持つシンプルなインターフェースとなります。

```swift:Disposable.swift
public protocol Disposable {
    func dispose()
}
```

このプロトコルの実装（具体的には `SubscriptionDisposable` など）については、ReactiveExtensions の `Observable` の本質とは少し離れ、かなり Swift という言語やメモリモデルに依存したものになるため、ひとまず後回しにして他の実装をみていくことにしましょう。


## 3.3. ObserverType, ObservableType プロトコルの定義

ObserverType, ObservableType プロトコルの定義については、ほとんど push 型の Observer パターンとかわりありません。変化しているのは「値がイベントという文脈付きで通知される」という点だけです。文脈がついているため、いままで `notify` と命名していた箇所が `on` という名前に変わっています。これは、引数に enum 値として `.next(Element)`, `.error(Error)`, `.completed` が渡ると考えると自然な命名ですね。

```swift:ObserverObservable.swift
public protocol ObservableType {
    associatedtype E
    func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E
}

public protocol ObserverType {
    associatedtype E
    func on(_ event: Event<E>)
}
```

　また、`ObserverType` には便利な拡張メソッドとして `onNext(Element)`, `onError(Error)`, `onCompleted` が生えています。

```swift:ObserverExtensions.swift
extension ObserverType {    
    public final func onNext(_ element: E) {
        on(.next(element))
    }
    
    public final func onCompleted() {
        on(.completed)
    }
    
    public final func onError(_ error: Swift.Error) {
        on(.error(error))
    }
}
```

## 3.4. Observable の実装

　つづいて Observable の実装についてみていきましょう。 基本的に `ObservableType` の関連型（associated type）を、型パラメータに引き上げる以外のことはやっていません。Swift には抽象クラスや抽象メソッドという言語機能が存在しないため、その意志を込めて `Never` 型を返すメソッドを呼び出しているのが特徴的です。

```swift:Observable.swift
public class Observable<Element>: ObservableType {
    public typealias E = Element
    
    public func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        abstractMethod()
    }
}

/// 抽象メソッドを表現するための苦肉の策
func abstractMethod() -> Never {
    fatalError("abstract method")
}
```


## 3.5. AnonymousObserver の実装

`AnonymousObserver` に関しても push 型 Observer パターンをベースに**「`next` 以外の値が飛んだ場合に、以後イベントは飛ばなくなる」**というルールが追加した実装に変更します。

```swift:AnonymousObserver.swift
class AnonymousObserver<Element>: ObserverType {
    typealias E = Element
    typealias EventHandler = (Event<Element>) -> Void
    private let eventHandler: EventHandler
    private var isStopped: Int32 = 0 //=> means AtomicInt
    
    public init(_ eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }

    public func on(_ event: Event<Element>) {
        switch (event) {
        case .next:
            if isStopped == 0 { eventHandler(event) }
        case .error, .completed:
            if !OSAtomicCompareAndSwap32Barrier(0, 1, &isStopped) { return }
            eventHandler(event)
        }
    }
}
```

　Swift では `Bool` を参照し、条件次第で異なる値を代入する操作はアトミックではないため、その代わりのフラグとして `Int32` が利用されています。また、 `OSAtomicCompareAndSwap32Barrier` は、値と変数を比較して等しい場合に、新しい値を代入する操作をアトミックに行うものです。この場合 `isStopped` が 0 と等しいか比較をして真であれば 1 に差し替えるという操作をアトミックに行います。このあたりは `AnonymousObserver` の本質的な部分でないため、難しければ理解しなくても大丈夫です。

## 3.6. RxSwift の Observable についてのまとめ

　歴史的経緯はどうだったのか知りませんが、Rx の基本的なインターフェースである `Observable`, `Observer` については以下のように説明できると思います（※筆者は歴史的経緯は知らないので実際の流れは違うかもしれません）。

1. push 型 Observer パターンが基本的な出発点
2. 通知する値に `.next`, `.error`, `.completed` という文脈をつけた `Event` が通知の対象物になっているのが特徴的
3. また `.next` 以外の値が通知されると以降、イベントは送られない（ストリームが閉じる）
4. 購読解除の仕組みを `Disposable` に分離しているのが特徴的

　以上を踏まえると `Observable`, `Observer` といったインターフェースを自然に導き出すことができると思います。ここまでくれば、`Observable` はもはや「川」といったあいまいなものではなく、よりビビッドに振る舞いを捉えることができるようになっているのではないでしょうか。


# 4. Subject と Disposable を実装する

　これまで観測可能な値(`Observable`)と、その状態変化を観測するオブジェクト(`Observer`)について詳しく見てきましたが、ReactiveExtensions にはそのどちらの役割も持つオブジェクトが存在します。それが、`Subject` です。代表的なものに `BehaviorSubject`, `PublishSubject` などがあります。

　`Observable` であり、かつ `Observer` であるということは単純に以下のような `SubjectType` プロトコルに落とし込むことができます。

```swift:SubjectType.swift
// 通知元にも通知先にもなりうるオブジェクトを表す
public protocol SubjectType: ObservableType { // 普段は Observable としてふるまう
    typealias SubjectObserverType: ObserverType

    func asObserver() -> SubjectObserverType // 必要なときに SubjectObserverType に変換できる
}
```

## 4.1. PublishSubject のふるまい

　`Observable` は、 `subscribe(Observer)` メソッドによって受け入れた `Observer` にイベント発生時に通知をするという働きをします。 `Observer` は発生したイベント値の通知を受け入れる `on(Event<T>)` というメソッドを持っています。

　`PublishSubject` は `Subject` であるため、 `on(Event<T>)` と `subscribe(Observer)` 双方のメソッドを持っています。ベーシックな使い方としては、 `PublishSubject` にあらかじめ `Observer` を `Subscribe` させておき、`on(Event<T>)` を読んだときに通知させるというものになります。これは先にみてきた Observer パターンと全く同じ構図になります。 `PublishSubject` というと得体の知れないものに聞こえるかも知れませんが、実態はこれまで散々見てきた Observer パターンのなかの Observable 具象クラスそのものと同じ立ち位置であるといえば、わかりやすいのではないかと思います。実際に動かしたいコードのイメージは以下のようになります。

```swift:PublishSubjectClientCode.swift
var isHoge = PublishSubject<Bool>()
var observer = AnonymousObserver<Bool>({ event in
    switch(event) {
    case .next(var value): NSLog(String(value))
    case .error(var error): NSLog(error.localizedDescription)
    case .completed: NSLog("completed")
    }
})
var disopsable = isHoge.subscribe(observer)
isHoge.on(Event.next(true))   //=> [LOG] `true`
isHoge.on(Event.next(false))  //=> [LOG] `false`
disopsable.dispose()
isHoge.on(Event.next(true))   //=> ログ出力されない
```

　push 型 Observer パターンでもみた風景ですね。これを実現するためには素直に Observable のインターフェースを実装していけば良いはずなので、書き出しは以下のような形になるかと思います。

```swift:PublishSubjectBeta.swift
public class PublishSubject<Element>: Observable<Element>, SubjectType, ObserverType {
    public typealias SubjectObserverType = PublishSubject<Element>
    var observers: [String:AnonymousObserver<Element>] = [:]
    
    public override func subscribe<O>
    (_ observer: O) -> Disposable where O : ObserverType, O.E == Element {
        // dictionary にしないと O : ObserverType, O.E == Element が
        // Equatable じゃないので削除（unsubscribe）できなくなる
        let key = UUID().uuidString
        observers[key] = AnonymousObserver(observer.on)
        fatalError()
    }
    
    public func on(_ event: Event<Element>) { observers.forEach { x in x.value.on(event) } }
    public func asObserver() -> PublishSubject<Element> { return self }
}
```

　ほぼ push 型 Observer パターンのときと同様です。しかしながら、まだ `Disposable` の具象クラスを実装していないため、`subscribe` の戻り値を生成できず、ひとまず `Never` 型を返す `fatalError` をよんでいます。直近の課題は、`subscribe` で返すべき `SubscriptionDisposable` というクラスを実装するというものになります。


## 4.2 SubscriptionDisposable の実装

　ここでの `Disposable` の責務は端的に言えば 「`unsubscribe` を呼び出す」というものになります。したがってまず、`PublishSubject` 自体に `unsubscribe` メソッドを生やしてしまいましょう。外部へは `Disposable` プロトコルで渡るため、internal スコープ内に `unsubscribe` メソッドを持つことを伝えるための `UnsubscribeType` というプロトコルも同時に切ると、以下のような形になります。

```swift:PublishSubjectBeta2.swift
protocol UnsubscribeType: class {
    func unsubscribe(key: String)
}

public class PublishSubject<Element>:
Observable<Element>, SubjectType, ObserverType, UnsubscribeType {
    public typealias SubjectObserverType = PublishSubject<Element>
    var observers: [String:AnonymousObserver<Element>] = [:]
    
    public override func subscribe<O>
    (_ observer: O) -> Disposable where O : ObserverType, O.E == Element {
        let key = UUID().uuidString
        observers[key] = AnonymousObserver(observer.on)
        //=> unsubscribe が以下のように実装されたので、key と 自分自身への弱参照を保持するオブジェクトを返せばよい
        fatalError() 
    }
    
    internal func unsubscribe(key: String) { observers.removeValue(forKey: key) }
    public func on(_ event: Event<Element>) { observers.forEach { x in x.value.on(event) } }    
    public func asObserver() -> PublishSubject<Element> { return self }
}
```

　`unsubscribe` がこのように実装されたため、`subscribe` ではこのオブジェクトへの弱参照と、引数で受け入れた observer に対応するキーを保持したオブジェクトを作ればよいことになります。

```swift:SubscriptionDisposable.swift
struct SubscriptionDisposable<T>: Disposable {
    weak var ref: UnsubscribeType?
    let key: String
    init(ref: UnsubscribeType, key: String) {
        self.ref = ref
        self.key = key
    }
    public func dispose() {
        ref?.unsubscribe(key: key)
    }
}
```

　こうして購読解除の仕組みを `Disposable` に閉じ込めることができました。`Disposable` は `unsubscribe` を発火させたい `Observable` を弱参照で持っているため、`Diposable` を扱うクラスと `Obseravble` の依存関係を晴れて参照レベルで断ち切ることができました。

## 4.3. PublishSubject と SubscribeDisposable

　最後に `PublishSubject` の `fatalError()` だった箇所を修正して、ひとまず PublishSubject としてのふるまいを実装できたことになります。

```swift:PublishSubject.swift
public class PublishSubject<Element>:
Observable<Element>, SubjectType, ObserverType, UnsubscribeType {
    public typealias SubjectObserverType = PublishSubject<Element>
    var observers: [String:AnonymousObserver<Element>] = [:]
    
    public override func subscribe<O>
    (_ observer: O) -> Disposable where O : ObserverType, O.E == Element {
        let key = UUID().uuidString
        observers[key] = AnonymousObserver(observer.on)
        return SubscriptionDisposable<Element>(ref: self, key: key)
    }
    
    internal func unsubscribe(key: String) { observers.removeValue(forKey: key) }

    public func on(_ event: Event<Element>) { observers.forEach { x in x.value.on(event) } }

    public func asObserver() -> PublishSubject<Element> { return self }
}

struct SubscriptionDisposable<T>: Disposable {
    weak var ref: UnsubscribeType?
    let key: String
    init(ref: UnsubscribeType, key: String) {
        self.ref = ref
        self.key = key
    }
    public func dispose() { ref?.unsubscribe(key: key) }
}
```

　これは RxSwift の実装と完全には一致しないのですが、本質的にはこのような構造を持つと思います。

## 4.4. （余談） 停止したストリームの subscribe と NopDisposable

　`.error`, `.completed` が飛んだあとに `Observable` を `subscribe` しても、以後イベントは飛ばないため意味がありません。このとき `subscribe` は `observer` コレクションへの追加を行わない実装になっており、コレクションからの削除を実行するためのオブジェクトである `Disposable` は何もしなくてもよいことになります。これに対応して、RxSwift には何もしない `Disposable` の実装として `NopDisposable` が用意されています。コードは非常に単純で次のとおりになります。

```swift:NopDisposable.swift
struct NopDisposable : Disposable {
    init() {}
    public func dispose() {}
}
```

実際の `PublishSubject` にはストリームが止まった以後の `subscribe` 時には `SubscriptionDisposable` ではなく `NopDisposable` が返されていますので興味のある方はみてみると良いと思います。


## 4.5. （余談） スレッドセーフにするために

　これまで実装した `PublishSubject` は `subscribe`, `dispose`, `on` の呼び出しに対してスレッドセーフではありません。RxSwift では `RecursiveLock` を使ってスレッドセーフとなるような記述が入っています。使い方は簡単で、以下のようなものです。

```swift:Lock1.swift
let lock = NSRecursiveLock()
lock.lock()
/*
 ここに排他したい処理を書く
 */
lock.unlock()
```

　RxSwift 内では特に以下のような書き方が目立ちます。これは排他したい区間（クリティカルセクション）での例外発生時にロックが解除されないことを防ぐ意図があると思われます。

```swift:Lock2.swift
何かのスコープ {
    let lock = NSRecursiveLock()
    lock.lock()
    defer { lock.unlock() } 
    /*
     ここに排他したい処理を書く
     */
}
```

興味のある方は、このあたりも意識しながら、ソースコードを読んでみると良いと思います。

## 4.6. （余談） Bag の実装

　observer を追加/削除できるコレクションとして今回は `UUID#uuidString` をキーとして [String:ObserverType] という dictionary を用いましたが、実際には `insert` 時にそれに対応するキーを発行してくれる Key-Value ストア `Bag` が用いられています。

```swift:Bag.swift
struct BagKey: Hashable {
    fileprivate let rawValue: UInt64
    var hashValue: Int { return rawValue.hashValue }
}
func ==(lhs: BagKey, rhs: BagKey) -> Bool { return lhs.rawValue == rhs.rawValue }

struct Bag<T> {
    typealias KeyType = BagKey
    typealias Entry = (key: BagKey, value: T)
    fileprivate var nextKey: BagKey = BagKey(rawValue: 0)
    var dictionary: [BagKey:T] = [:]
    
    init() { }
    
    mutating func insert(_ element: T) -> BagKey {
        let key = _nextKey
        nextKey = BagKey(rawValue: nextKey.rawValue &+ 1)
        dictionary[key] = element
        return key
    }
    
    mutating func removeAll() {
        dictionary.removeAll(keepingCapacity: false)
    }
    
    mutating func removeKey(_ key: BagKey) -> T? {
        return dictionary.removeValue(forKey: key)
    }
    
    func forEach(_ action: (T) -> Void) {
        for element in dictionary.values {
            action(element)
        }
    }
}
```

　ご覧の通り `insert` された順に単純に 0 オリジンで key が発行される仕組みです。`&+` は加算に用いるオーバーフロー演算子で、オーバーフローを許容してくれます。実際の RxSwift の `Bag` の実装はもう少し工夫をして、要素が少ないときに最適化がかかるようなコードになっているようですが、本質を取り出すとこのような実装になるかと思います。実際のコードを読むときはこのあたりの大枠を知っているほうがコードリーディングしやすいと思いますので、ここに記載しておきます。


# 5. まとめ

* RxSwift は Observer パターンからの発展を考えることによりインターフェースやその実装を導くことができました
* 一見複雑そうに見える構造も、要求される仕様から自ずと導かれるインターフェースとなっていることがわかったのではないでしょうか
* 設計は基本的に問題を解決するものであり、問題を正しく見抜いたり、設定したりすることが、必要な解を見出す近道になるのではないでしょうか
* 複雑そうに見えるパターンも単純な原理原則に分解できるケースが多いのではないでしょうか

というような偉そうなことをいってまとめとしたいと思います。これからもどのような設計がどのような状況で必要なのかを引き続き考えていきたいと思います。RxSwift はそのヒントを与えてくれる良質なコードとなっていると個人的には思います。


# 6. ライセンス表記

RxSwift は MIT ライセンスで公開されています。記事内のコードはライセンスに基づき、そのまま掲載している箇所や改変して掲載している箇所があります。

> The MIT License Copyright © 2015 Krunoslav Zaher All rights reserved.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
> 
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


