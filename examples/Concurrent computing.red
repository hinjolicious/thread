Red [
	title: "Synchronous concurrency"
	author: "hinjolicious"
]

#include %thread.red

foreach msg ["Enjoy" "Rosetta" "Code"] [
	THREAD/spawn msg to-time 0.001 object [
		go: 1
		task-func: func [/local self][self: THREAD/task
			switch go [
			1 [	self/sleep-ticks random 10 go: 2 ]
			2 [	print self/id return 'finished ]
			]
			'yield
		]
	]
]

THREAD/run/tick-delay 00:00:00.01
