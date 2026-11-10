// Business-hours helpers.
// Format: "Mon-Fri 10:30-19:00; Sat 10:30-17:00"  (days not listed = closed)

const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

function toMinutes(hhmm) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm.trim());
  if (!m || Number(m[1]) > 24 || Number(m[2]) > 59) {
    throw new Error(`Bad time "${hhmm}" - use 24-hour HH:MM, e.g. 19:00`);
  }
  return Number(m[1]) * 60 + Number(m[2]);
}

function dayIndex(name) {
  const i = DAYS.indexOf(name.trim().slice(0, 3).toLowerCase());
  if (i === -1) throw new Error(`Bad day "${name}" - use Mon, Tue, Wed, ...`);
  return i;
}

function parseHours(spec) {
  const schedule = Array.from({ length: 7 }, () => []);
  for (const part of spec.split(';').map((p) => p.trim()).filter(Boolean)) {
    const m = /^([A-Za-z]+)(?:\s*-\s*([A-Za-z]+))?\s+(\S+)\s*-\s*(\S+)$/.exec(part);
    if (!m) throw new Error(`Bad business hours "${part}" - e.g. "Mon-Fri 10:30-19:00"`);
    const [, fromDay, toDay, open, close] = m;
    const start = dayIndex(fromDay);
    const end = toDay ? dayIndex(toDay) : start;
    const range = { open: toMinutes(open), close: toMinutes(close) };
    for (let d = start; ; d = (d + 1) % 7) {
      schedule[d].push(range);
      if (d === end) break;
    }
  }
  return schedule;
}

// Day of week and minutes past midnight for `date` in the given time zone.
function localTime(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const get = (type) => parts.find((p) => p.type === type).value;
  return { day: dayIndex(get('weekday')), minutes: Number(get('hour')) * 60 + Number(get('minute')) };
}

function isOpen(schedule, timeZone, date = new Date()) {
  const { day, minutes } = localTime(date, timeZone);
  return schedule[day].some((r) => minutes >= r.open && minutes < r.close);
}

module.exports = { parseHours, isOpen };
