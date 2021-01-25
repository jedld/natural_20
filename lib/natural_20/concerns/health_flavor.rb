# typed: false
module Natural20::HealthFlavor
  def describe_health
    return '' if hp.zero? || hp.negative?

    percentage = (hp.to_f / max_hp) * 100

    token = if dead?
              'dead'
            elsif unconscious?
              'unconscious'
            elsif percentage > 90
              'max'
            elsif percentage > 75
              'over_75'
            elsif percentage > 50
              'over_50'
            elsif percentage > 25
              'over_25'
            elsif percentage > 10
              'over_10'
            else
              'almost_dead'
            end
    t("entity.health_flavor.#{token}")
  end
end
