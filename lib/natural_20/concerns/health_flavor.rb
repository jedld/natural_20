module HealthFlavor
  def describe_health
    return '' if hp.zero?

    percentage = (hp.to_f / max_hp) * 100

    if percentage > 75
      "doesn't show any signs of slowing, just a few minor inconveniencing injuries"
    elsif percentage > 50
      'visibly wounded with some nondebilitating injuries, but still fighting strong'
    elsif percentage > 25
      'starting to look more ragged or visibly slowing down'
    elsif percentage > 10
      'looking in bad condition, unable to fight or survive much longer'
    else
      'barely hanging on, one more solid blow may take them down'
    end
  end
end
