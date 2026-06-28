# Translates kube-score JSON v2 output to SonarCloud Generic External Issues format.
#
# Usage:
#   jq -f kube-score-to-sonar.jq kube-score-report.json > sonar-issues.json
#
# Environment variables (set before running jq):
#
#   KUBE_SCORE_PATH_PREFIX  — strip this prefix from file_name (e.g. an absolute path root)
#     export KUBE_SCORE_PATH_PREFIX="$(Build.SourcesDirectory)/"
#
#   KUBE_SCORE_PATH_PREPEND — prepend this to every filePath after stripping (e.g. a subdirectory)
#     export KUBE_SCORE_PATH_PREPEND="deployment/"
#
# Both are optional and independent. A common AZDO pattern when kube-score runs inside
# a subdirectory called "deployment" but SonarCloud analyzes from the repo root:
#   export KUBE_SCORE_PATH_PREPEND="deployment/"

($ENV.KUBE_SCORE_PATH_PREFIX  // "") as $pathPrefix
| ($ENV.KUBE_SCORE_PATH_PREPEND // "") as $pathPrepend
| . as $input
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
          cleanCodeAttribute: "CONVENTIONAL",
          type: "CODE_SMELL",
          severity: (if $minGrade == 1 then "CRITICAL" else "MAJOR" end),
          impacts: [
            {
              softwareQuality: (if $minGrade == 1 then "RELIABILITY" else "MAINTAINABILITY" end),
              severity: (if $minGrade == 1 then "HIGH" else "MEDIUM" end)
            }
          ]
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
                { message: $check.check.name, filePath: ($pathPrepend + ($obj.file_name | ltrimstr($pathPrefix))) }
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
                      filePath: ($pathPrepend + ($obj.file_name | ltrimstr($pathPrefix)))
                    }
                    + (if $obj.file_row > 0 then { textRange: { startLine: $obj.file_row } } else {} end)
                  )
                }
            )
        end
      | .[]
    ]
  }
