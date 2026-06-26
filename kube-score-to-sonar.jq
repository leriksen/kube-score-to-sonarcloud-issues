# Translates kube-score JSON v2 output to SonarCloud Generic External Issues format.
#
# Usage:
#   jq -f kube-score-to-sonar.jq kube-score-report.json > sonar-issues.json
#
# If file_name values are absolute paths, strip the project root prefix:
#   jq --arg root "$(Build.SourcesDirectory)/" -f kube-score-to-sonar.jq report.json > sonar-issues.json
# Then replace `$obj.file_name` below with `($obj.file_name | ltrimstr($root))`.

. as $input
| (
    [
      $input[]
      | .checks[]
      | select(.skipped == false and .grade <= 5)
    ]
  ) as $failing
| {
    rules: [
      $failing
      | group_by(.check.id)[]
      | (map(.grade) | min) as $minGrade
      | .[0].check
      | {
          id: .id,
          name: .name,
          description: (.comment // .name),
          engineId: "kube-score",
          type: "CODE_SMELL",
          severity: (if $minGrade == 1 then "CRITICAL" else "MAJOR" end)
        }
    ],
    issues: [
      $input[] as $obj
      | $obj.checks[] as $check
      | select($check.skipped == false and $check.grade <= 5)
      | if ($check.comments | length) == 0 then
          [
            {
              ruleId: $check.check.id,
              primaryLocation: (
                { message: $check.check.name, filePath: $obj.file_name }
                + (if $obj.file_row > 0 then { textRange: { startLine: $obj.file_row } } else {} end)
              )
            }
          ]
        else
          $check.comments
          | map(
              . as $c
              | ([$c.summary, $c.description] | map(select(. != null and . != "")) | join(". ")) as $detail
              | {
                  ruleId: $check.check.id,
                  primaryLocation: (
                    {
                      message: (if ($c.path // "") != "" then "\($c.path): \($detail)" else $detail end),
                      filePath: $obj.file_name
                    }
                    + (if $obj.file_row > 0 then { textRange: { startLine: $obj.file_row } } else {} end)
                  )
                }
            )
        end
      | .[]
    ]
  }
