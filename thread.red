Red [
	Title:		"Cooperative Micro-Threading Library for Red"
	Author:		"hinjolicious"
	File:		%thread.red
	Description: {
		Cooperative micro-thread scheduler using Red map! for O(1) task 
		lookup with comprehensive task and scheduler telemetry.
	}
	Credits:	"Gemini AI"
]

; ===================================================================
; 1. CHANNEL DATA STRUCTURE
; ===================================================================

make-channel: func [capacity [integer!]] [
	object [
		cap: capacity
		buffer: copy []
		puts-count: 0
		gets-count: 0
		
		put: func [val [any-type!]] [
			either (length? buffer) < cap [
				append/only buffer val
				puts-count: puts-count + 1
				true	; successful put
			][ false ]	; failed put (buffer full)
		]
		
		get: func [] [
			either empty? buffer [ none ] [
				gets-count: gets-count + 1
				take buffer
			] 
		]
		
		peek:	   func [] [ either empty? buffer [ none ] [ first buffer ] ]
		ch-full?:  func [] [ (length? buffer) >= cap ]
		ch-empty?: func [] [ empty? buffer ]
		count:	   func [] [ length? buffer ]
		ch-clear:  func [] [ clear buffer ]
		
		telemetry: func [] [
			make map! compose [
				capacity	(cap)
				count		(length? buffer)
				total-puts	(puts-count)
				total-gets	(gets-count)
			]
		]
	] ; /channel object
] ; /make-channel


; ===================================================================
; 2. MAP-BASED SCHEDULER ENGINE
; ===================================================================

THREAD: context [
	tasks:			 make map! 100
	task:			 none		  ; current active task
	running?:		 false
	tick:			 0
	on-tick:		 none ; <-- universal hook for visualization, etc.
	
	; Global Telemetry Counters
	total-slices:	 0
	total-execs:	 0
	broadcast-count: 0
	run-start-time:	 none
	run-end-time:	 none

	reset: func [] [ 
		clear tasks	 
		running?:		 false
		tick:			 0 
		total-slices:	 0
		total-execs:	 0
		broadcast-count: 0
		run-start-time:	 none
		run-end-time:	 none
	]
	
	get-task: func [id] [ tasks/:id ]

	; --- Task Spawner ---
	
	spawn: func [
		task-id			[integer! string! word!] 
		slice-duration	[time!] 
		inner-obj		[object!]	; user code
		/local task-wrapper
	][
		task-wrapper: object [
			id:				task-id
			inner:			inner-obj	 ; user code
			slice:			slice-duration
			state:			'ready		 ; 'ready, 'waiting, 'done
			wait-ticks:		0
			wait-until:		none
			mailbox:		copy []
			
			; --- Detailed Task Telemetry ---
			slice-count:	0			 ; Number of times scheduled into time-slice
			exec-count:		0			 ; Total task-func calls
			sleep-count:	0
			mail-sent:		0
			mail-recv:		0
			broadcast-sent: 0
			cpu-time:		00:00:00
			created-time:	now/time/precise
			completed-time: none
			created-tick:	THREAD/tick
			completed-tick: none
			
			; --- O(1) Direct Mail Dispatch by ID, String, or Word ---
			
			send-mail: func [target [integer! string! word!] msg /local target-task] [
				if all [
					target-task: THREAD/tasks/:target
					target-task/state <> 'done 
				][
					append/only target-task/mailbox msg
					mail-sent: mail-sent + 1
					true
				]
			]
			
			read-mail: func [] [
				if empty? mailbox [ return none ]
				mail-recv: mail-recv + 1
				take mailbox
			]

			peek-mail: func [] [ if empty? mailbox [ none ] [ first mailbox ] ]
			
			publish: func [msg] [ 
				broadcast-sent: broadcast-sent + 1
				THREAD/broadcast msg 
			]
			
			; --- Wait Timers ---
			
			sleep-ticks: func [n [integer!]] [
				sleep-count: sleep-count + 1
				wait-ticks: n
				state: 'waiting
			]
			
			sleep: func [t [time!]] [
				sleep-count: sleep-count + 1
				wait-until: now/time/precise + t
				state: 'waiting
			]
			
			finish: func [/telemetry /local stats] [
				state: 'done
				completed-tick: THREAD/tick
				completed-time: now/time/precise
				
				if telemetry [ probe THREAD/task-telemetry self ]
				'finished
			]
		] ; /task-wrapper object
		
		tasks/:task-id: task-wrapper
		task-wrapper
	]

	; --- System-Wide Broadcast ---
	
	broadcast: func [msg] [
		broadcast-count: broadcast-count + 1
		foreach [id task] tasks [
			if task/state <> 'done [
				append/only task/mailbox msg
			]
		]
	]

	; --- Core Scheduler Tick --- 

	step-func: func [/local t-now signal start-t t0 t1 t-diff] [
		tick:	tick + 1
		t-now:	now/time/precise
		
		if none? run-start-time [ run-start-time: t-now ]

		foreach [id task] tasks [
			if task/state = 'done [ continue ]
				
			; 1. Process Wait Timers
			
			if task/state = 'waiting [
				if task/wait-ticks > 0 [ task/wait-ticks: task/wait-ticks - 1 ]
				if all [task/wait-until t-now >= task/wait-until] [ task/wait-until: none ]
				if all [task/wait-ticks <= 0 task/wait-until = none] [ task/state: 'ready ]
			]

			; 2. Execute Time Slice
			
			if task/state <> 'ready [ continue ]
			
			start-t: now/time/precise
			task/slice-count: task/slice-count + 1
			THREAD/total-slices: THREAD/total-slices + 1
			
			while [
				all [
					(now/time/precise - start-t) < task/slice
					task/state = 'ready
				]
			][
				t0: 	now/time/precise
				signal: task/inner/task-func 
				t1: 	now/time/precise
				
				t-diff: 		 t1 - t0
				task/exec-count: task/exec-count + 1
				task/cpu-time:	 task/cpu-time + t-diff
				
				THREAD/total-execs: THREAD/total-execs + 1
				
				switch/default signal [
					yield	 [ break ]
					continue [ 'keep-looping ]
					finished [ 
						task/state:			 'done
						task/completed-tick: tick
						task/completed-time: now/time/precise
						break
					]
				][ break ] ; default fallback
			]
		] ; /foreach tasks loop
		
		if :on-tick [ on-tick ] ; <-- executes after all coroutines complete 1 tick
	] ; /step-func

	; --- Scheduler Controls --- 
	
	run: func [/tick-delay delay [time!]] [
		run-start-time:	now/time/precise
		run-end-time:	none
		running?:		true
		
		while [running?] [
			step-func
			if delay [ wait delay ]
			if all-done? [ 
				running?: 	  false 
				run-end-time: now/time/precise
			]
			do-events/no-wait ; <-- let other events fires
		]
	]
	
	stop: func [] [ running?: false  run-end-time: now/time/precise ]

	all-done?: func [] [
		foreach [id task] tasks [
			if task/state <> 'done [ return false ]
		]
		true
	]
	
	; ===================================================================
	; 3. TELEMETRY REPORTING API
	; ===================================================================

	telemetry: func [
		/local active waiting done total-cpu wall-t avg-slice cpu-pct
	][
		active: waiting: done: 0  
		total-cpu: 00:00:00
		
		foreach [id task] tasks [
			switch task/state [
				ready	[ active:  active  + 1 ]
				waiting [ waiting: waiting + 1 ]
				done	[ done:	   done	   + 1 ]
			]
			total-cpu: total-cpu + task/cpu-time
		]
		
		wall-t: either run-start-time [
			(any [run-end-time now/time/precise]) - run-start-time
		][ 00:00:00 ]
		
		avg-slice: either total-slices > 0 [ total-cpu / total-slices ] [ 00:00:00 ]
		
		cpu-pct: either all [wall-t > 00:00:00  wall-t <> 00:00:00] [
			round/to ((to-float total-cpu) / (to-float wall-t) * 100) 0.01
		][ 0.0 ]
		
		make map! compose [
			current-tick		(tick)
			total-tasks			(length? tasks)
			active-tasks		(active)
			waiting-tasks		(waiting)
			done-tasks			(done)
			broadcast-count		(broadcast-count)

			total-slices		(total-slices)
			total-execs			(total-execs)
			
			avg-slice-cpu		(avg-slice)
			total-cpu-time		(total-cpu)
			total-wall-time		(wall-t)
			cpu-utilization-pct (cpu-pct)		; total-cpu-time / total-wall-time
		]
	]
	
	task-telemetry: func [
		t [object!]
		/local end-t end-k wall-t total-k avg-exec avg-slice
	][
		unless t [ return none ]
		
		end-t:	 any [t/completed-time now/time/precise]
		end-k:	 any [t/completed-tick THREAD/tick]
		wall-t:	 end-t - t/created-time
		total-k: end-k - t/created-tick
		
		avg-exec:  either t/exec-count > 0	[ t/cpu-time / t/exec-count ]  [ 00:00:00 ]
		avg-slice: either t/slice-count > 0 [ t/cpu-time / t/slice-count ] [ 00:00:00 ]
		
		make map! compose [
			id					(t/id)
			state				(t/state)
			sleep-count			(t/sleep-count)
			mail-sent			(t/mail-sent)
			mail-recv			(t/mail-recv)
			broadcast-sent		(t/broadcast-sent)
			mailbox-pending		(length? t/mailbox)
			
			created-tick		(t/created-tick)
			completed-tick		(t/completed-tick)
			total-ticks			(total-k)
			total-slices		(t/slice-count)
			exec-count			(t/exec-count)

			budget-slice		(t/slice)			
			avg-slice-cpu		(avg-slice)
			avg-exec-cpu		(avg-exec)
			cpu-time			(t/cpu-time)
			wall-time			(wall-t)
		]
	]
]
