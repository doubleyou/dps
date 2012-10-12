#!/usr/bin/env node


var client = require("redis").createClient();
var counter = 1;
var start = new Date();
 
client.on("error", function (err) {
        console.log("Error: ", err);
});


setInterval(function() {
  var delta = (new Date()) - start;
  console.log("" + Math.round(counter*1000 / delta) + " msg/s");
}, 1000);
 
client.on("ready", function () {
        var f = function (g) {
                counter++;
                client.publish("ch-1", "Message " + counter);
                // (counter % 10000 == 0) && (console.log(counter));
                g(f);
        };
 
        var g = function (f) {
                process.nextTick(function () { f(g); });
        };
 
        f(g);
});

