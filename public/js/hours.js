// Use this file to dynamically highlight a list of days/hours for PCA
$(document).ready(function () {
  const d = getESTDate();     // Date in EST time
  const day_num = d.getDay(); // 0 is Sunday
  const hr_num = d.getHours();
  const s = $('.opening-hours li').eq(day_num);

  s.addClass('active'); // Add active class to the day of the week in the list

  const day_check = day_num > 0 && day_num < 6;   // Not Mon or Sun
  const hr_check = hr_num > 7 && hr_num < 18;     // 8 - 6
  if (day_check && hr_check) {  // Prepend the Open badge to the hour span
    const inner_str = '<span class="d-none d-sm-inline"> Now</span>';  // Hide the 'Now' on small screens
    const str = '<span class="ml-3 badge badge-success">Open' + inner_str + '</span>';
    s.children().before(str)
  }
});

function getESTDate() {
  const offset = -5.0; // EST
  const clientDate = new Date();
  const utc = clientDate.getTime() + (clientDate.getTimezoneOffset() * 60000);
  return new Date(utc + (3600000 * offset));
}
