
function getFixItJson(params){
 $.ajax({
      type: "GET",
      url: "http://192.168.1.100/fixit-api/api.pl",
       data: {payload_json: JSON.stringify(params)},
       success: function(msg){
         //alert(msg);
         return msg;
       }
      });

}
