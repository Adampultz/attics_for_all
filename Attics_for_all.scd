s.meter;
s.plotTree;
s.boot;
s.options.sampleRate_(44100);

MIDIFunc.trace(true)
MIDIFunc.trace(false)
(

//1. server config
s = Server.local;
s.options.outDevice_(
	 //"Built-in Output"
   //"Fireface UCX (23732049)"
	"Komplete Audio 6"
);

~sampleRate = 48000;
~nyquistDur = (~sampleRate / 1).reciprocal;

s.options.numOutputBusChannels_(8);
s.options.inDevice_(
	// "Fireface UCX (23732049)"
	"Komplete Audio 6"
);

s.options.numInputBusChannels_(6);
//s.options.hardwareBufferSize_(32);
s.options.sampleRate_(~sampleRate);
s.options.memSize_(2.pow(20));
s.options.blockSize_(64);
//s.options.latency_(0.02);
s.newBusAllocators;
s.recChannels_(8);

ServerBoot.removeAll;
ServerTree.removeAll;
ServerQuit.removeAll;
MIDIIn.connectAll;

~numNodes = 4;
~makeBusses = {
	~pots = 8.collect { |i| Bus.control(s, 1)};
	~sliders = 8.collect { |i| Bus.control(s, 1)};
	~audio = ~numNodes.collect({ |i| Bus.audio(s, 1)});
	~out = ~numNodes.collect({ |i| Bus.audio(s, 1)});
	~trig = Bus.audio(s,1);
	~dur =  ~numNodes.collect({ |i| Bus.control(s).set(0.01)});
	~specC =  ~numNodes.collect({ |i| Bus.control(s).set(440 )});
	~specCDiff = ~numNodes.collect({ |i| Bus.control(s).set(0)});
	~specFlat = ~numNodes.collect({ |i| Bus.control(s).set(0)});
	~specCdeviation = Bus.control(s, ~numNodes).set(1 ! 4);
	~pitch = ~numNodes.collect({ |i|Bus.control(s,1).set(440)});
	~rate = ~numNodes.collect({ Bus.control(s,1).set(20)});
	~listen = ~numNodes.collect({ |i| Bus.audio(s,1)});
	~probPhasor = ~numNodes.collect({ Bus.control(s,1).set(0)});
	~outSend = ~numNodes.collect({ Bus.audio(s,1)});
};

~makeArrays = {
	~synths = Dictionary.new;
	~pRateW = ~numNodes.collect({ |i|  0.5 + 5/(1 + i).sqrt});
	~recState = ~numNodes.collect({ |i| 0});
	~recDecision = ~numNodes.collect({ |i| 0});
	~probPhasorState = ~numNodes.collect({ |i| 0});
	~probPhasorStateArray = Array.fill(~numNodes, {0})
};



~makeControllers = {
	8.collect{|i| MIDIFunc.cc({arg val; ~sliders[i].set(val.linlin(0,127, -60.0,0))}, i, 0, -1137067586)}; // NK2
	8.collect{|i| MIDIFunc.cc({arg val; ~pots[i].set(val.linlin(0,127, 0,1))}, i+16, 0, -1137067586)}; // NK2
	~pots[0].set(0.02);
	~pots[1].set(0);

};

~makeBuffers = {
	// ~recBuf = ~numNodes.collect({ ~bufMono});
	~recBuf = 	~numNodes.collect({ |i| Buffer.alloc(s, s.sampleRate * 10.0, 1)});
};

~makeEnvelopes = {
	~env_qgauss = Env([0, 1, 1, 0], [0.25, 0.5, 0.25], \sin);
	~env_welch = Env([0, 1, 1, 0], [0.25, 0.5, 0.25], \welch);
};

~makeOSC = {
	~numNodes.collect({ |i| // Playback OSC control

		 OSCFunc({ arg msg, time;
			Synth("\playback_%".format(i), [\trig, msg[3], \buf, ~recBuf[i]], ~grainGrp); // trigger grains
		},"/reply_%".format(i), s.addr);


		OSCFunc({ arg msg, time; // Record OSC control
			//msg[4].postln;
	//msg.postln;
	if(msg[3] > 0.015) // If amplitude threshold is crossed
			{ if (~recDecision[i] == 0) // If no choice has yet been mande
				{if (~recState[i] == 0) // If recording is off
					{if ((0.5 / ~numNodes).coin == true) // Should buffer record?
						{
							~record[i].set(\recOn, 1); // If yes, set record state to on
							~recState.put(i, 1);
						"buffer % is recording".format(i);
							~recDecision.put(i, 1); // Notify that a choice has been made
						}
							{"buffer % is recording".format(i);
							~recDecision.put(i, 1); // Notify that a choice has been made
						}      // If no
					}
				{"buffer % is recording".format(i)} // If recording is on
				}
				{if (~recState[i] == 0) // If not recording
			{if(~probPhasorState[i] == 0) // If phasor state is off
		{~probPhasorState.put(i, 1); // Set phasor state to on
							~synths.add("\phasor_" ++ i -> Synth("\phasorCount_" ++ i, target: ~listenGrp))} // Create synthdef for phasor
						{if(msg[4].coin == true) // If coin calls true (probability = phasor)
							{~record[i].set(\recOn, 1); // Set record state to on
							~recState.put(i, 1); // Set record state to on
						"buffer % is recording".format(i);
							~recDecision.put(i, 1); // Notify that a choice has been made
							~probPhasorState.put(i, 0); // Set phasor state to off
								//(~phasorCount_ ++ i).free; // Free phasor
							~probPhasor[i].set(0); // Set phasor to 0

			}{"buffer % is not recording".format(i)}}
			}
	{"buffer % is recording".format(i)}}}
					{                            // If amplitude falls below threshold
				~record[i].set(\recOn, 0); // Set record state to off
				~recState.put(i, 0);
				~recDecision.put(i, 0); // Reset record decision
				~probPhasorState.put(i, 0); // Reset phasor state
				~probPhasor[i].set(0); // Set phasor to 0
		"buffer % is not recording".format(i)
}
		},"/listen_%".format(i), s.addr)

	});
	};

~makeRoutines = {
		Task({
		inf.do({ |n|
			var x = ~numNodes.collect{ |i|  ~specC[i].getnSynchronous};
			var a = ~numNodes.collect{ |i| x}.mean;
			~numNodes.collect({ |i|
				~specCdeviation.setAt(i, (a / x[i].clip(20.0, 6000)))
			});
		0.1.wait});
	}).start;

};

~cleanup = {
	s.newBusAllocators;
	ServerBoot.removeAll;
	ServerTree.removeAll;
	ServerQuit.removeAll;
};

~makeNodes = {
	s.bind({
		~inGrp = Group.new;
		~synthGrp = Group.new(~inGrp, \addAfter);
		~grainGrp = Group.new(~synthGrp, \addAfter);
		~listenGrp = Group.new(~grainGrp, \addAfter);
		~outGrp = Group.new(~listenGrp, \addAfter);
		~numNodes.collect({ |i|	"~phasor_" ++ i = Synth("\phasor_" ++ i, [\buf, ~recBuf[i]],~inGrp)});
		~out_ = ~numNodes.collect({ |i|	 Synth("\out_" ++ i, target: ~listenGrp)});
		~record = ~numNodes.collect({ |i| Synth("\record_%".format(i), [\buf, ~recBuf[i]], ~synthGrp)});
		~numNodes.collect({ |i| "~listen_" ++ i = Synth("\listen_" ++ i, target: ~listenGrp)});
		~realOut = Synth(\realOut, target: ~outGrp)
	});
};


ServerBoot.add(~makeBusses);
ServerBoot.add(~makeBuffers);
ServerBoot.add(~makeEnvelopes);
ServerBoot.add(~makeOSC);
ServerBoot.add(~makeControllers);
ServerBoot.add(~makeArrays);

ServerQuit.add(~cleanup);

s.waitForBoot({
s.sync;


	~numNodes.collect({ |i|

		SynthDef("\phasorCount_" ++ i,
			{ |dur = 50|
				var line = XLine.ar(0.00001, 1.0, dur: dur, doneAction: 2);
				Out.kr(~probPhasor[i], line)
		}).add;


		SynthDef("\record_" ++ i,
			{ |recOn = 0, buf|
				var trig = Impulse.ar(10);
				var in = HPF.ar(SoundIn.ar(0), 30);
				var in2 = SoundIn.ar(1);
				var delIn = DelayC.ar(in, 0.2, 0.1);
				var amp = Amplitude.ar(in);
				var rec = RecordBuf.ar(delIn, buf, recLevel: 0.9, preLevel: 0.1, run: recOn
				); // Write audio into buffer. Old data is overwritten by a ratio of 9/10
				SendReply.ar(trig, "/listen_%".format(i), [amp, ~probPhasor[i].kr]);
				Out.ar(2, in2)
	}
).add;

		SynthDef("\phasor_" ++ i,
	{|rate=0.1, buf|
				/*var rateP = RMS.kr(((Integrator.kr(~pitch[i].kr, ~pots[3].kr.clip(0, 0.99999)) * ~specCdeviation.kr(1, i).pow(2).clip(0.0001, 5))).clip(6, 150), 5);*/
				var rateP = OnePole.kr(((Integrator.kr(~pitch[i].kr, ~pots[3].kr.clip(0, 0.99999)) * ~specCdeviation.kr(1, i).pow(2).clip(0.0001, 5))).clip(6, 150), 1 - (5 * ~nyquistDur));
				var trig = Impulse.ar(rateP);
				var frames = BufFrames.kr(buf);
				var start = Phasor.ar(0.0, BufRateScale.kr(buf) * OnePole.kr(~specFlat[i].kr, 1 - (10 * ~nyquistDur)), 0, frames - 1);
				Out.ar(~audio[i], start);
				Out.kr(~dur[i], rateP);
				SendReply.ar(trig, "/reply_%".format(i) , trig)
}).add;

		SynthDef("\playback_" ++ i,
	{|dur = 0.1, trig=0, buf, sustain = 0.01|
				var in = ~audio[i].ar;
				var pBack = PlayBuf.ar(1,  buf, 1, trig, in);
				var env = ~env_welch;
				var envCtl = EnvGen.ar(env,trig, 1,0, (~dur[i].kr.reciprocal + sustain), doneAction: 2);
				var out = pBack*envCtl;
				Out.ar(~listen[i], out);
				Out.ar(~out[i], out * ~sliders[i].kr.dbamp * (1 / ~numNodes));

				SynthDef("\out_" ++ i, {
					|coef = 0.1|
					var in = ~out[i].ar;
					var comb = CombC.ar(in, 0.2, 440.reciprocal, decaytime: 0.1);
					var combMix = XFade2.ar(in, comb, (-1 + LPF.kr((1 - ~specCdeviation.kr(1, i)), 2).abs.pow(2).clip(0,1.0)));
					var int = Integrator.ar(combMix, ~pots[2].kr.linlin(0, 1, 0, 0.999));
					Out.ar(i + 4, int);
					Out.ar(~outSend[i], int)
	}).add;

}).add;


	SynthDef("\listen_" ++ i, {
		|coeff = 0.8, oStatWinS = 2, thres = 0.15|
		var in = ~listen[i].ar;
		var chain = FFT(LocalBuf(2048), in);
		var onsetChain = FFT(LocalBuf(512), in);
		var amplitude = Amplitude.ar(in);
		var specCent = OnePole.kr(SpecCentroid.kr(chain), 1 - (5 * ~nyquistDur));
		var specFlat = Integrator.kr(SpecFlatness.kr(chain), (10 * specCent.reciprocal.sanitize));
		var pitch = Pitch.kr(in);
		var pitchDiff = OnePole.kr(pitch[0], 1 - ~nyquistDur);
		var onset = Onsets.kr(onsetChain, thres);
		var density = OnsetStatistics.kr(onset, oStatWinS)[0];
		pitchDiff = (pitch[0] - pitchDiff).abs.reciprocal.sqrt.sanitize;
		pitch = Amplitude.kr(pitch[0].sqrt * pitchDiff, 0.2, 0.2); // Try with One-Pole version
		/*pitch = OnePole.kr(pitch[0].sqrt * pitchDiff, 0.2);*/
		pitch = Integrator.kr(pitch, coeff);
		Out.kr(~pitch[i], pitch);
		Out.kr(~specC[i], specCent);
		Out.kr(~specFlat[i], specFlat)
	}).add;
	});

							SynthDef(\realOut, {
			var in = ~numNodes.collect({ |i| ~outSend[i].ar});
			Out.ar(0, Splay.ar(in));
			Out.ar(2, SoundIn.ar(0));
			Out.ar(3, SoundIn.ar(1));
	}).add;

			s.sync;

	//6b. register remaining functions

	ServerTree.add(~makeNodes);
	ServerTree.add(~makeRoutines);


	s.freeAll;
	s.sync;
	"done".postln;
});
)

