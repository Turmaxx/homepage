---
title: "Concurrency Abstractions in Go: Queues, Tasks, and Actors"
date: 2023-07-11T15:58:14+03:00
draft: false
tags: ["go", "concurrency", "actor-model"]
---

# Introduction

Concurrency is built-in to the Go programming language and is one of the most powerful features of the language.
There are many great resources that explain how concurrency works out of the box in Go.
This post will cover a basic overview of how concurrency works in Go and then explore some concurrency abstractions that are common in other languages and how they can be implemented in Go.
This post will also cover some basic usage of generics and managing state with closures.

Note that one of the characteristics of Go is that it does not rely on as many abstractions as other languages and more direct approaches are common.
The patterns presented here are more for learning and exploring with comparisons to other languages rather than for actual use.
Error handling is not directly addressed in any of these examples as well.

{{< lead >}}
Code for this post can be found at [GitHub](https://github.com/turmaxx/concurrency-abstractions-in-go) or [GitLab](https://gitlab.com/brook-seyoum/concurrency-abstractions-in-go).
{{< lead >}}

## Go Concurrency Fundamentals

Go has two primary features for handling concurrency: `goroutines` and `channels`.

### Goroutines

A `goroutine` is a lightweight, virtual process that is managed by a built-in scheduler.
`Goroutines` are lighter weight than threads in other languages and are created by calling the `go` keyword followed by a function call.
For example:

```go
func main() {
  go func() {
    fmt.Println("Hello, World!")
  }()
}
```

This code snippet will create a new `goroutine` that will print "Hello, World!" to the console in the background.
It is important to note that `goroutines` on their own do not provide any way to wait for execution to complete or to communicate with other `goroutines`.
This is where `channels` come in.

### Channels

A channel in Go is a special data structure that behaves like a queue that can be accessed by multiple `goroutines`.
Items can be either sent into the channel or received from the channel.
Channels provide the ability for `goroutines` to communicate with each other.
This allows data to be passed in and out of `goroutines` and for `goroutines` to wait for data to be available.
They also allow for synchronization of `goroutines` to ensure that they are executed in a particular order.
If the example above was run in an empty program it would not print anything since the main `goroutine` would exit before the `goroutine` that prints "Hello, World!" could finish.
Channels can be used to wait for the `goroutine` to finish before exiting the program.

```go
// helloworld.go
func helloworld() {
  c := make(chan struct{})
  go func() {
    fmt.Println("Hello, World!")
    c <- struct{}{}
  }()
  <-c
}
```

{{< lead >}}
The `struct{}` type is used here due to its minimal size. Another popular option for a signal channel like this is a `bool`.
{{< /lead >}}

In this example the data in the channel does not matter.
Instead we are using a special feature of channels that the receive operation will block until data is available.
When the empty struct is sent into the channel in the `goroutine` the receive operation in the main `goroutine` will unblock and the program will exit having printed the greeting.

Channels can also be closed which signals that no more data will be sent into the channel and any blocking receive operation should unblock.
In our example here this is not necessary since we are only sending a single item into the channel and only waiting for one item to be received.

An additional way to receive data from a channel is to use a `for` loop and the `range` keyword.
Channels can also be buffered, see this Go by Example [post](https://gobyexample.com/channel-buffering) for more details.

## Work Queues

Channels in Go are basically queues so a work queue concurrency abstraction makes sense in Go.
A work queue is a queue of tasks that are executed by a pool of workers.
The number of workers should be configurable and typically makes sense to set to the number of CPU cores.
An example work queue implementation is shown below.

```go
// workers.go
type Workers[T any] struct {
	Work chan func() T
	Results chan T
	wg sync.WaitGroup
}

func New[T any](numWorkers int) *Workers[T] {
	w := &Workers[T]{
		Work: make(chan func() T),
		Results: make(chan T),
		wg: sync.WaitGroup{},
	}

	for i := 0; i < numWorkers; i++ {
		w.wg.Add(1)
		go func() {
			for f := range w.Work {
				w.Results <- f()
			}
			w.wg.Done()
		}()
	}

	// Close the results channel when the work is done.
	go func() {
		w.wg.Wait()
		close(w.Results)
	}()

	return w
}
```

In this example we create a `Workers` struct that has a `Work` channel for tasks and a `Results` channel for results.
The struct has a generic type parameter to allow a variety of result types.
We could allow for input arguments explicitly here but our earlier trick of using closures works here as well since we are using a function as the work item type.
The struct also stores a wait group to manage synchronization of the workers so that we can close the results channel when all the work is done.
The constructor for this struct accepts a number of workers to create and starts a go routine for each worker that is listening to the work channel to take on work as it comes in.
As work is performed the result is sent to the results channel.
The following shows how this can be used.

```go
w := workers.New[string](2)
go func() {
  for i := 0; i < 10; i++ {
    i := i
    w.Work <- func() string {
      return fmt.Sprintf("%d", i)
    }
  }
  close(w.Work)
}()
for r := range w.Results {
  fmt.Println(r)
}
```

{{< lead >}}
Note that the `Workers` struct exposes a basic `Work` channel that is not buffered.
Since the channel will block on send we must send our work items in a separate go routine that will close the channel once all work has been added.
If we knew ahead of time how much work we would have we could create a buffered channel of the appropriate size.
{{< /lead >}}

## Tasks

Other languages provide a `Task` concurrency abstraction that allows for asynchronous execution code with explicit synchronization or "awaiting".
Sometimes this behavior is called a `promise` or `future`.

### Basic Task Implementation

The following is an implementation of a `Task` abstraction in Go based loosely on the .NET `Task`.

```go
// task.go
func New(f func()) *Task {
	return &Task{
		f:       f,
		awaiter: make(chan struct{}),
	}
}

func (t *Task) Start() {
	go func() {
		t.f()
		t.awaiter <- struct{}{}
	}()
}

func (t *Task) Wait() {
	<-t.awaiter
}
```

To use this `Task` abstraction we can create a new `Task` and call `Start` to start the `Task` in a new `goroutine`.
We then call `Wait` to wait for the `Task` to complete.
The awaiter channel is used to block the `Wait` call until the provided function has completed.

```go
t := New(func() {
  fmt.Println("Hello, World!")
})
t.Start()
t.Wait()
```

This implementation is very simple and does not provide any error handling or cancellation.
It also only implements functions that take no arguments and return no values.

### Task with Input Arguments

If we want to use a function with arguments with our `Task` we can use a closure to capture the arguments.
This example uses a similar function except the `greeting` to print is set in the outside scope and passed in as a closure.

```go
greeting := "Hello from the closure!"
t := New(func() {
  fmt.Println(greeting)
})
t.Start()
t.Wait()
```

{{< lead >}}
Note that the usual [caveats](https://github.com/golang/go/wiki/CommonMistakes#using-goroutines-on-loop-iterator-variables) about closures apply here and loop scope variables should be used with care and set as local variables when necessary. In this [proposal](https://github.com/golang/go/issues/20733) this might be changing.
{{< /lead >}}

### Task with Output Values

If we want to return a value from the `Task` we can also use a closure to capture the return value.
This example defines a variable in the outside scope and modifies it in the `Task` function.

```go
var greeting string
t := New(func() {
  greeting = "Hello from the closure!"
})
t.Start()
t.Wait()
fmt.Println(greeting)
```

Using closures like this works but it can be hard to determine what the actual inputs and outputs of the `Task` are.
We also need to pay more attention to the scoping of our variables than seems necessary.

### Refactoring with Generic Helpers

We can update our `Task` implementation to use some generic helpers to make the code more readable and easier to use.
Since we have already proven that the closure method works for input and outputs we can take advantage of that and not modify existing code.
To allow the creation of a task with a single input argument we can create the following helper function.

```go
// Creates a new task with a single input argument.
func NewWithInput[T any](f func(T), input T) *Task {
	fun := func() {
		f(input)
	}
	return New(fun)
}

// usage
t := NewWithInput(func(i string) {
  fmt.Println(i)
}, "Hello with generics!")
t.Start()
t.Wait()
```

This helper function takes a function that takes a single argument and a value to pass into that function.

To allow a task to return a value we must slightly modify the `Task` struct to store the return value.
We create a new constructor function to simplify creation of the new struct and a getter function to get the result after blocking on the execution of the task.

```go
// Task struct that stores a single result value.
type TaskWithResult[T any] struct {
	Task
	result T
}

// Creates a new task that stores a single result value.
func NewWithResult[T any](f func() T) *TaskWithResult[T] {
	t := &TaskWithResult[T]{
		Task: *New(nil),
	}
	t.f = func() {
		t.result = f()
	}
	return t
}

// Returns the result value after waiting for the task to finish.
func (t *TaskWithResult[T]) GetResult() T {
	t.Wait()
	return t.result
}
```

This new constructor closes over its own container struct in order to store the result value.
Using these new features are straightforward and shown in the following example.
`GetResult` is called rather than `Wait` so that we get the result value after the task has finished.

```go
t := NewWithResult(func() string {
  return "Hello with generic output!"
})
t.Start()
fmt.Println(t.GetResult())
```

These approaches can be combined based on the needed input and output tasks of the application.
Unfortunately we would need to create a new version of these functions and wrapper structs for every variation.
If we were building a library we would not want to create a new function for every possible number of arguments.
Code generation and reflection could help solve this but we won't explore that now.

## Actor Model

The actor model is a concurrency abstraction that is based on the idea of actors that communicate with each other via messages.
An actor can only do three things when receiving a message: mutate internal state, send a message to another actor, and create new actors. [^actor]
Message sending is asynchronous and non-blocking by default so the order of messages is not guaranteed.
The actor is the base unit of computation and they compose to form larger systems.
One of the interesting properties of an actor model based system is that there is no shared state between actors.
This allows for greater fault tolerance and easier reasoning about the system.

This pattern has been implemented in many languages and is a proven approach to distributed systems.
Erlang and other BEAM languages such as Elixir are built around this concept.
BEAM languages use an abstraction on top of the actor model known as OTP (Open Telecom Platform)[^otp] that forms a powerful framework for building distributed systems.
For a Go implementation of OTP see https://github.com/ergo-services/ergo.
This example implementation of the actor model is more basic.

An extra benefit of the actor model is that it can be easily scaled out to a distributed system where the actors are running on different machines though we won't cover that case here.

[^actor]: See https://www.brianstorti.com/the-actor-model/ for a good introduction to the actor model as well as https://en.wikipedia.org/wiki/Actor_model for more history and detail.
[^otp]: See https://github.com/erlang/otp and https://erlang.org/download/armstrong_thesis_2003.pdf for more information on OTP.

### Actors

In Go, `goroutines` make a great foundation for actors as Erlang processes do for BEAM languages.
On top of the virtualized lightweight unit of computation we only need to add a message queue to create an actor.
Some synchronization is also necessary in to improve the usability of the actor.

This example creates a simple `Actor` struct that wraps up a configurable actor implementation with a message queue and a wait group for synchronization.
The handling of messages is configured at construction via a function that is stored in the struct.

```go
// actor.go
type Actor[T any] struct {
	messages chan T
	handler  func(T)
	wg       sync.WaitGroup
}

// Creates a new actor with the given handler function.
func New[T any](handler func(T)) *Actor[T] {
	a := &Actor[T]{
		messages: make(chan T),
		handler:  handler,
	}
	go func() {
		for m := range a.messages {
			a.handler(m)
			a.wg.Done()
		}
	}()
	return a
}

// Sends a message to the actor.
func (a *Actor[T]) Send(m T) {
	a.wg.Add(1)
	go func() {
		a.messages <- m
	}()
}

// Waits for all messages to be finished and closes the channel.
func (a *Actor[T]) Stop() {
	a.wg.Wait()
	close(a.messages)
}
```

The `Actor` struct has a generic type parameter to allow for a variety of message types.
It implements a `Send` method that adds the message to the message queue and increments the wait group.
This is done asynchronously so that the caller does not block though the wait group ensures that when we stop the actor it drains existing messages.
Asynchronous message sending is expected in an actor model based system.
The `Stop` method waits for all messages to be processed and then closes the message queue.

{{< lead >}}
Note that the `messages` channel is not buffered and we are able to accept multiple messages because we are using a goroutine to send and process each message.
{{< /lead >}}

See the following snippet for usage of this struct.
In this example we create a simple actor that prints out the message it receives.

```go
a := actor.New(func(s string) {
    fmt.Println(s)
})
a.Send("Hello, World!")
a.Send("Hello again, World!")
a.Stop()
```

The messages will not always be printed in the order they were sent because actors are asynchronous and non-deterministic by default.

### Specialized Actors

The `Actor` struct we built above is a generic implementation that can be expanded upon to create more specialized actors.
In this example we create a specialized actor that prints every message (of type string) it receives.

```go
// printer.go
type Printer struct {
	*Actor[string]
}

func NewPrinter() *Printer {
	p := &Printer{}
	p.Actor = New(func(s string) {
		fmt.Println(s)
	})
	return p
}

func (p *Printer) Print(s string) {
	p.Send(s)
}
```

All we are doing to the generic `Actor` is creating a custom constructor and wrapping the `Send` method with a more specific name.
The following snippet shows how this would be used to perform the same task as the generic `Actor` example above.

```go
p := actor.NewPrinter()
p.Print("Hello, World!")
p.Print("Hello again, World!")
p.Stop()
```

The output is the same but we get a little bit more reusability and better readability with our specialized actors.

### Multiple Actors

Actors are rarely useful on their own.
Instead, they are typically composed into larger systems that accomplish more complex tasks.
In this example we create two types of actors: a `ChatRoom` and a `Client`.
The `ChatRoom` is responsible for printing any message it receives along with the sender's name.
The `Client` is responsible for sending messages to the `ChatRoom`.

```go
// chat_room.go
type ChatRoom struct {
	*Actor[message]
}

// Creates a new chat room that prints messages that come in.
func NewChatRoom() *ChatRoom {
	c := &ChatRoom{}
	c.Actor = New(func(m message) {
		fmt.Printf("%s: \t %s\n", m.sender.name, m.text)
	})
	return c
}

type Client struct {
	*Actor[string]
	name string
}

// Creates a new client that sends messages to the given chat room.
func NewClient(name string, room *ChatRoom) *Client {
	c := &Client{
		name: name,
	}
	c.Actor = New(func(t string) {
		m := message{
			sender: c,
			text:   t,
		}
		room.Send(m)
	})
	return c
}

type message struct {
	sender *Client
	text   string
}
```

All we need to do to implement this is create custom types and constructors for each actor type that sets their message handling behavior as well as create a small custom struct to serve as the message type.
This snippet shows these actors in action.

```go
// create chat room
chatRoom := actor.NewChatRoom()

// create clients
alice := actor.NewClient("Alice", chatRoom)
bob := actor.NewClient("Bob", chatRoom)

// send messages
alice.Send("Hello, Bob!")
bob.Send("Hello, Alice!")

// stop actors and wait for them to finish
alice.Stop()
bob.Stop()
chatRoom.Stop()
```

The `chatroom` actor is constructed, then two clients are created with the `chatroom` pointer as an input so that their handlers know which actor to send messages to.
The clients then send messages to each other and the `chatroom` prints them out.
Finally, all actors are stopped and the program exits.

{{< lead >}}
Note that the actors must be stopped in this example so that we make sure to wait for all messages to be processed since they are passing asynchronously.
{{< /lead >}}

More advanced actors might accept multiple types of messages and have more complex message handling logic.
They may also store more complex state.
Supervisor actors that manage other actors and enhance fault tolerance are also common.

## Conclusions

The fundamental building blocks of Go allow for some expressive and powerful concurrency patterns.
Despite the fact that in reality most usages of concurrency would be more bespoke, the basic tools of Go allow for a lot of flexibility.

Some future exploration could include:

- More complex actor systems and a more thorough implementation of the actor model
- Event based concurrency patterns
- Performance benchmarking of the different approaches and comparison with other languages
- Error handling and fault tolerance
- Using buffering to improve performance and change behavior of the channels

## Further Reading

[The Go Programming Language](https://www.gopl.io/) by Alan A. A. Donovan and Brian W. Kernighan is a great resource for understanding Go and has thorough descriptions of concurrency in Go.

[Go By Example](https://gobyexample.com/) has useful examples of Go features including those for concurrency.