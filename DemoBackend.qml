import QtQuick
import "Api.js" as Api
import "Demo.js" as Demo

// In-memory implementation of LiveBackend's request/supersede interface.
QtObject {
  id: root

  property int generation: 0

  function success(data) {
    return {
      "ok": true,
      "status": 200,
      "kind": "",
      "error": "",
      "data": data
    };
  }

  function queryValue(path, name) {
    var match = String(path || "").match(new RegExp("(?:[?&])" + name + "=([^&]*)"));
    return match ? decodeURIComponent(match[1]) : "";
  }

  function request(path, callback) {
    var text = String(path || ""), data = {
    };
    if (text.indexOf("/stop_finder") !== -1)
      data = {
      "locations": Demo.locations(queryValue(text, "name_sf"))
    };
    else if (text.indexOf("/departure_mon") !== -1)
      data = {
      "stopEvents": []
    };
    else if (text.indexOf("/trip") !== -1)
      data = {
      "journeys": []
    };
    callback(success(data));
    return {
      "abort": function() {
      }
    };
  }

  function probe(callback) {
    callback(success({
    }));
  }

  function departures(callback) {
    callback(success(Demo.board(Date.now())));
  }

  function searchStops(text, callback) {
    callback(success(Demo.locations(text)));
  }

  function plan(callback) {
    callback(success(Demo.journeys(Date.now())));
  }

  function supersede() {
    generation++;
  }

  function reset() {
    generation++;
  }
}
