Red [
	title: "Synchronous concurrency"
	author: "hinjolicious"
]

#include %thread.red

CHANNEL: make-channel 3

THREAD/spawn 'READER 00:00:00.01 object [
	buf: 	none
	step:	'start
	task-func: func [/local self] [ self: THREAD/task
		switch step [
			start 		 [ buf: read/lines %input.txt			step: 'push-channel	]
			push-channel [ CHANNEL/put take buf					step: 'check-eof	]
			check-eof	 [ either empty? buf [ step: 'how-many ]
											 [ step: 'push-channel ] ] 
			how-many 	 [ self/send-mail 'PRINTER "How many?"	step: 'check-count	]
			check-count  [ either empty? lines: self/read-mail [ step: 'check-count ]
															   [ print ["Lines:" lines]
																 return 'finished ] ]
		]
		'yield
	]
]

THREAD/spawn 'PRINTER 00:00:00.01 object [
	step: 1
	count: 0
	task-func: func [/local self item] [ self: THREAD/task
		switch step [
			1 [ unless CHANNEL/ch-empty? [ 
					item: CHANNEL/get  
					count: count + 1  
					print item 
				]
				step: 2
			  ]
			2 [ mail: self/read-mail 
				either mail = "How many?" [
					self/send-mail 'READER form count
					return 'finished
				][ step: 1 ]
			  ]
		]
		'yield
	]
]

THREAD/run/tick-delay 00:00:00.01

print "^/Task Telemetry:"
probe THREAD/task-telemetry THREAD/get-task 'READER
probe THREAD/task-telemetry THREAD/get-task 'PRINTER
probe THREAD/telemetry