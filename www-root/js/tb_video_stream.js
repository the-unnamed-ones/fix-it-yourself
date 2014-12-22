;
(function(VS) {
    'use strict';

    VS.VideoStreamer = function(){

        var currentVideoStream = null;

        this.startStream = function(videoElement, stream){
            var video = true;

            if(stream) {
                var video = {
                  optional: [{
                    sourceId: stream,
                  }],
                };
            }

            if (!!currentVideoStream) {
                videoElement.src = null;
                currentVideoStream.stop();
            }


            navigator.getUserMedia = (navigator.getUserMedia ||
                                 navigator.webkitGetUserMedia ||
                                 navigator.mozGetUserMedia ||
                                 navigator.msGetUserMedia);

            if (navigator.getUserMedia){
                navigator.getUserMedia({
                    video: video,
                    audio:false
                    },        
                    function(stream){
                        currentVideoStream = stream;
                        var url = window.URL || window.webkitURL || window.mozURL;

                        videoElement.src = url ? url.createObjectURL(stream) : stream;
                        videoElement.play();
                    },
                    function(error){
                        console.log('An error occured while trying to start video stream.');
                    }
                );
            }else {
                console.log('Sorry, the browser you are using doesn\'t support getUserMedia');
                return;
            }  
        };

        this.stopStream = function(videoElement){
            console.log(currentVideoStream);

            if(typeof(currentVideoStream.stop()) == 'function'){
                videoElement.src = '';
                currentVideoStream.stop(); 
            }    
        }

        this.takePicture = function(videoElement,imageElement,type,encoderOptions){
            var url = window.URL || window.webkitURL || window.mozURL;

            var canvas = document.createElement("canvas");
                canvas.width = videoElement.videoWidth;
                canvas.height = videoElement.videoHeight;
                canvas.getContext('2d')
                    .drawImage(videoElement, 0, 0, canvas.width, canvas.height);

            imageElement.src = canvas.toDataURL(type,encoderOptions);
        }
    }
    window.VS = VS;
})(window.VS || {});