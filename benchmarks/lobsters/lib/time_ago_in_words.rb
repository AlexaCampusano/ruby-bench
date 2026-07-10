module TimeAgoInWords
  def time_ago_in_words(time)
    secs = (Time.current - time).to_i
    if secs <= 5
      "just now"
    elsif secs < 60
      "less than a minute ago"
    elsif secs < (60 * 60)
      mins = secs / 60
      mins == 1 ? "1 minute ago" : "#{mins} minutes ago"
    elsif secs < (60 * 60 * 48)
      hours = secs / 3600
      hours == 1 ? "1 hour ago" : "#{hours} hours ago"
    elsif secs < (60 * 60 * 24 * 30)
      days = secs / 86400
      days == 1 ? "1 day ago" : "#{days} days ago"
    elsif secs < (60 * 60 * 24 * 365)
      months = secs / 2592000
      months == 1 ? "1 month ago" : "#{months} months ago"
    else
      years = secs / 31536000
      years == 1 ? "1 year ago" : "#{years} years ago"
    end
  end
end
