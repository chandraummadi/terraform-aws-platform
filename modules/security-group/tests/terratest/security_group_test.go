package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSecurityGroupBasicExample applies examples/basic, asserts against real
// AWS state via the SDK, and destroys in a deferred cleanup even on
// assertion failure — per docs/coding-standards.md §8.
func TestSecurityGroupBasicExample(t *testing.T) {
	t.Parallel()

	awsRegion := "us-east-1"

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../examples/basic",
		Vars: map[string]interface{}{
			"aws_region": awsRegion,
		},
		NoColor: true,
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	sgID := terraform.Output(t, terraformOptions, "security_group_id")
	require.NotEmpty(t, sgID)

	// --- Real AWS state assertions, not just TF output ---------------------
	sg := aws.GetSecurityGroupById(t, sgID, awsRegion)
	require.NotNil(t, sg)

	// Exactly one ingress rule (HTTPS/443) and one egress rule (all traffic).
	assert.Len(t, sg.IpPermissions, 1, "expected exactly one ingress rule")
	assert.Len(t, sg.IpPermissionsEgress, 1, "expected exactly one egress rule")

	ingress := sg.IpPermissions[0]
	assert.EqualValues(t, 443, *ingress.FromPort)
	assert.EqualValues(t, 443, *ingress.ToPort)
	assert.Equal(t, "tcp", *ingress.IpProtocol)

	ingressRuleIDs := terraform.OutputMap(t, terraformOptions, "ingress_rule_ids")
	egressRuleIDs := terraform.OutputMap(t, terraformOptions, "egress_rule_ids")
	require.Len(t, ingressRuleIDs, 1)
	require.Len(t, egressRuleIDs, 1)
	assert.Contains(t, ingressRuleIDs, "https")
	assert.Contains(t, egressRuleIDs, "all_outbound")
}
