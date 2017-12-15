$(document).ready(function () {
  const q = ['fail', 'dumb', 'silly',
    'funny', 'hilarious', 'error', 'lol'][new Date().getDay()]; // semi-random search query
  const api_key = 'dc6zaTOxFJmzC';    // your giphy API key
  let request = new XMLHttpRequest;
  request.open('GET', 'http://api.giphy.com/v1/gifs/random?api_key=' + api_key + '&tag=' + q, true);
  request.onload = function () {
    if (request.status >= 200 && request.status < 400) {
      const data = JSON.parse(request.responseText).data.image_url;
      const str = '<img src="' + data + '"  title="GIF via Giphy" class="img-fluid d-block w-100 mb-3">';
      $("#giphyme").append(str)
    } else {
      console.log('Reached giphy, but API returned an error');
    }
  };
  request.onerror = function () {
    console.log('Connection error');
  };
  request.send();

});