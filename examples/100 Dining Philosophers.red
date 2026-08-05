Red [
	Title: "Dining Philosophers - Ego Dynamics Simulation (THREAD)"
]

#include %THREAD.red

PHILOSOPHERS: [
	"Ptahhotep" "Kagemni" "Zarathustra" "Moses" "Laozi" "Confucius" "Sun Tzu" 
	"Mahavira" "Buddha" "Anaximander" "Thales" "Anaximenes" "Pythagoras" 
	"Xenophanes" "Heraclitus" "Parmenides" "Mozi" "Melissus" "Zeno" "Empedocles" 
	"Anaxagoras" "Leucippus" "Protagoras" "Gorgias" "Prodicus" "Hippias" 
	"Antiphon" "Democritus" "Socrates" "Critias" "Antisthenes" "Aristippus" 
	"Euclid" "Diogenes" "Isocrates" "Plato" "Speusippus" "Xenocrates" "Aristotle" 
	"Pyrrho" "Theophrastus" "Crates" "Stilpo" "Mencius" "Xunzi" "Han Feizi" 
	"Shen Dao" "Zhuangzi" "Hui Shi" "Epicurus" "Cleanthes" "Chrysippus" 
	"Arcesilaus" "Carneades" "Panaetius" "Posidonius" "Philo" "Cicero" "Lucretius" 
	"Varro" "Seneca" "Musonius" "Epictetus" "Plutarch" "Dio" "Marcus Aurelius" 
	"Favorinus" "Gellius" "Alcinous" "Numenius" "Sextus" "Alexander" "Plotinus" 
	"Porphyry" "Iamblichus" "Longinus" "Laertius" "Lactantius" "Arnobius" 
	"Eusebius" "Basil" "Nazianzus" "Nyssa" "Ambrose" "Jerome" "Chrysostom" 
	"Augustine" "Hypatia" "Theodoret" "Proclus" "Dionysius" "Boethius" 
	"Damascius" "Simplicius" "Philoponus" "Isidore" "Maximus" "Aspasia" 
	"Aspasius" "Aenesidemus" "Hermarchus" "Metrodorus" "Crantor"
]

NUM-PHILS: 51
NUM-MEALS: 5
FORKS: append/dup copy [] none NUM-PHILS

PHIL-COLOR: #[
	thinking: blue
	hungry:	  orange
	waiting:  red
	eating:	  leaf
	done:	  coal
]

FORK-COLOR-FREE: silver 
TABLE-COLOR:	 coal / 3

THREAD-SLICE:	00:00:00.001
THINK-DUR:		00:00:00.1		; THINK-DUR + random THINK-RAND
THINK-RAND:		0.5
EAT-DUR:		00:00:00.1		; EAT-DUR + (ego-level * EAT-EGO)
EAT-EGO:		0.5
PATIENCE-DUR:	00:00:00.5		; PATIENCE-DUR * ego-level, low ego surrender sooner

;; ===================================================================
;; PHILOSOPHER TASK WITH EGO DYNAMICS
;; ===================================================================

spawn-phil-task: func [id [integer!] name [string!] ego [integer!]][
	THREAD/spawn id THREAD-SLICE object [
		phil-id:	 id
		phil-name:	 name
		ego-level:	 ego			  ;; 1 (Humble/Yielding) to 10 (Greedy/Stubborn)
		done?:		 false
		state:		 'thinking
		held-forks:	 copy []		  ;; Currently grabbed fork indices
		wait-start:	 none			  ;; Timestamp when entering waiting state

		target-time: now/time/precise + THINK-DUR + random THINK-RAND
		meals-left:	 NUM-MEALS
		
		task-func: func [/local self t-now free-idx f patience-limit][
			self: THREAD/task
			t-now: now/time/precise
			
			switch state [
				thinking [
					either t-now >= target-time [
						state: 'hungry
						'continue
					][
						'yield
					]
				]
				
				hungry [
					;; Snatch 1 fork to begin
					free-idx: collect [
						repeat i NUM-PHILS [ if FORKS/:i = none [ keep i ] ]
					]
					unless empty? free-idx [
						f: free-idx/1
						FORKS/:f: phil-id
						append held-forks f
					]
					
					state: 'waiting
					wait-start: t-now  ;; Start patience timer for 2nd fork
					'yield
				]
				
				waiting [
					;; Attempt to grab the 2nd fork if we only have 1
					if (length? held-forks) < 2 [
						free-idx: collect [
							repeat i NUM-PHILS [ if FORKS/:i = none [ keep i ] ]
						]
						unless empty? free-idx [
							f: free-idx/1
							FORKS/:f: phil-id
							append held-forks f
						]
					]

					either (length? held-forks) = 2 [
						state: 'eating
						target-time: t-now + EAT-DUR + (ego-level * EAT-EGO)
						'continue
					][
						;; Check patience limit based on ego level
						patience-limit: PATIENCE-DUR * ego-level
						
						either (t-now - wait-start) > patience-limit [
							;; VOLUNTARY RELEASE: Low ego surrenders held fork to unblock others
							foreach f held-forks [ FORKS/:f: none ]
							clear held-forks
							
							state: 'thinking  ;; Back off to thinking state!
							target-time: t-now + THINK-DUR + random THINK-RAND
							'yield
						][
							'yield	  ;; Continue holding 1 fork while waiting
						]
					]	  
				]
				
				eating [
					either t-now >= target-time [
						;; Return held FORKS back to global pool
						foreach f held-forks [ FORKS/:f: none ]
						clear held-forks
						
						meals-left: meals-left - 1
						either meals-left <= 0 [
							state: 'done
							return self/finish ;/telemetry ; <-- Uses THREAD finish helper
						][
							state: 'thinking
							target-time: t-now + THINK-DUR + random THINK-RAND
							'yield
						]
					][
						'continue
					]
				]
			]
		] ; /task-func
	]
]

font-label:	   make font! [ name: "Arial" size: 7 color: white ]
font-complete: make font! [ name: "Arial" size: 14 style: 'bold color: yellow ]

;; --- Fixed Geometry Setup ---
canvas-size: 1000
center-x: center-y: canvas-size / 2
margin-pct:	 0.1
r-max:		 (canvas-size / 2.0) * (1.0 - margin-pct)  ;; 475.0 px

gap-factor:	 0.25	;; 25% spacing gap between neighbor nodes
table-scale: 0.98	;; Table takes 98% of inner boundary
max-node-r:	 70.0	;; Upper bound cap for small N

;; ===================================================================
;; DYNAMIC RENDERING ENGINE
;; ===================================================================

render-table: function [][
	angle-step: 360.0 / max 1 NUM-PHILS
	sin-half:	sine (angle-step / 2.0)

	phil-r: (r-max * sin-half) / (1.0 + gap-factor + sin-half)
	phil-r: min max-node-r phil-r

	phil-orbit: r-max - phil-r

	inner-boundary: r-max - (2.0 * phil-r)
	table-r:		to-integer (inner-boundary * table-scale)

	f-size: max 7 min 12 to-integer (phil-r * 0.25)
	font-label/size: f-size
	fork-r: max 2 to-integer (phil-r * 0.22)	
	fork-orbit-r: table-r - (fork-r * 4)
	
	; draw table
	draw-blk: reduce [ 'pen 'off  'fill-pen TABLE-COLOR	 'circle as-pair center-x center-y table-r ]

	; draw free forks
	repeat i NUM-PHILS [
		f-ang: ((i - 1) * angle-step) + (angle-step / 2.0) - 90
		fx: center-x + to-integer (fork-orbit-r * cosine f-ang)
		fy: center-y + to-integer (fork-orbit-r * sine f-ang)
		append draw-blk reduce [ 'fill-pen FORK-COLOR-FREE	'circle as-pair fx fy fork-r ]
	]
	
	;; --- Draw Philosopher Nodes ---
	repeat i NUM-PHILS [
		p-ang: ((i - 1) * angle-step) - 90
		px: center-x + to-integer (phil-orbit * cosine p-ang)
		py: center-y + to-integer (phil-orbit * sine p-ang)
		
		p: THREAD/get-task i
		if p [
			; draw philosopher node
			append draw-blk reduce [ 'fill-pen PHIL-COLOR/(p/inner/state)  'circle as-pair px py phil-r ]
			
			; draw held forks
			foreach f-idx p/inner/held-forks [
				f-ang: ((f-idx - 1) * angle-step) + (angle-step / 2.0) - 90
				fx: center-x + to-integer (fork-orbit-r * cosine f-ang)
				fy: center-y + to-integer (fork-orbit-r * sine f-ang)
				
				holder: FORKS/:f-idx
				if holder [
					h-ang: ((holder - 1) * angle-step) - 90
					hx: center-x + to-integer (phil-orbit - (phil-r * 0.95) * cosine h-ang)
					hy: center-y + to-integer (phil-orbit - (phil-r * 0.95) * sine h-ang)
					
					append draw-blk reduce [
						'pen PHIL-COLOR/(p/inner/state)	 'line-width max 1 to-integer (phil-r * 0.12)
							'line as-pair fx fy as-pair hx hy
						'pen 'off
					]
				]
			]		 

			;; Dynamic Level-of-Detail Text String
			p-name: p/inner/phil-name
			text-blk: reduce [
				rejoin [p-name " (" p/inner/ego-level ")"]
				form p/inner/state
				either NUM-PHILS <= 70 [
					rejoin [
						either p/inner/meals-left > 0 [ 
							rejoin ["m:" form p/inner/meals-left "/" form NUM-MEALS " "] 
						][""]
						either empty? p/inner/held-forks [""][
							rejoin ["f:" form p/inner/held-forks] 
						]	 
					]
				][""]
			]

			text-str: to-string collect [foreach e text-blk [keep e keep "^/"]]
			line-cnt: length? text-blk
			
			tx: px - to-integer (phil-r * 0.85)
			ty: py - to-integer (line-cnt * (f-size + 2)) / 2
			
			either NUM-PHILS <= 50 [
				append draw-blk reduce [
					'font font-label  'pen white  'text as-pair tx ty text-str	'pen 'off
				]
			][ ; rotate label
				either (cosine p-ang) >= 0 [
					rot-ang: p-ang
					tx: px - (phil-r * 0.8)
				][
					rot-ang: p-ang + 180.0
					tx: px + (phil-r * 0.8) - to-integer (f-size * (length? text-blk/1) * 0.6)
				]
				append draw-blk reduce [
					'push reduce [
						'rotate rot-ang as-pair px py  'font font-label	 'pen white	 
						'text as-pair tx ty text-str
					]
				]
			]	 
		]
	]

	;; --- Completion Overlay via Telemetry ---
	stats: THREAD/telemetry
	if all [stats/total-tasks > 0 stats/active-tasks = 0] [
		append draw-blk reduce [
			'font font-complete	 'pen yellow  'text as-pair (center-x - 70) (center-y - 10) "Dinner's ended!"
		]
	]

	canvas-face/draw: draw-blk
	if canvas-face/state [ show canvas-face ]
]

;; ===================================================================
;; VIEW LAYOUT & SIMULATION INIT
;; ===================================================================
is-running?: false
init-simulation: func [][
	random/seed 1 ;now/time/precise
	
	THREAD/reset
	FORKS: append/dup copy [] none NUM-PHILS
	repeat p NUM-PHILS [
		spawn-phil-task p PHILOSOPHERS/:p (1 + random 9)
	]
	THREAD/on-tick: :render-table ; <-- inject rendering engine to the scheduler hook
	render-table
]

;win: view/tight/no-sync/no-wait [
win: view/tight/no-sync [
	title "Dining Philosophers - Ego Dynamics Simulation (THREAD)"
	canvas-face: box with [size: as-pair canvas-size canvas-size] black 
	return
	panel [
		pad 20x0 btn-run: button "Start Simulation" [
			either THREAD/running? [
				btn-run/text: "Resume"  show btn-run
				THREAD/stop  
			][
				btn-run/text: "Pause" show btn-run
				stats: THREAD/telemetry
				if any [stats/total-tasks = 0 stats/active-tasks = 0] [ init-simulation ]
				THREAD/run
			]
		]
		pad 20x0 text "Philosophers (1-100):" np: field 30 [print face/text]
		pad 20x0 text "Meals:" 35 nm: field 30 [print face/text]
		pad 20x0 btn-reset: button "Reset" [
			inp: to-integer np/text
			if any [inp < 1	 inp > 100] [alert "1 to 100 only!" exit]
			NUM-PHILS: inp
			NUM-MEALS: to-integer nm/text
			init-simulation
			btn-run/text: "Start Simulation" show btn-run
		]
	]
	do [
		np/text: to string! NUM-PHILS
		nm/text: to string! NUM-MEALS
		init-simulation
	]
]

; if using no-wait (auto-end after finished):
;while [all [win/state  not thread/all-done?]] [
;	do-events/no-wait
;]
