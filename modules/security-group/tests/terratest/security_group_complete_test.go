package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSecurityGroupCompleteExample applies examples/complete, asserts
// against real AWS state via the SDK, and destroys in a deferred cleanup
// even on assertion failure — per docs/coding-standards.md §8.
func TestSecurityGroupCompleteExample(t *testing.T) {
	t.Parallel()

	awsRegion := "us-east-1"

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../examples/complete",
		Vars: map[string]interface{}{
			"aws_region": awsRegion,
		},
		NoColor: true,
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	sgID := terraform.Output(t, terraformOptions, "security_group_id")
	require.NotEmpty(t, sgID)

	sg := aws.GetSecurityGroupById(t, sgID, awsRegion)
	require.NotNil(t, sg)

	// 7 ingress rules declared in examples/complete.
	assert.Len(t, sg.IpPermissions, 7, "expected 7 ingress rules")
	assert.Len(t, sg.IpPermissionsEgress, 1, "expected 1 egress rule")

	ingressRuleIDs := terraform.OutputMap(t, terraformOptions, "ingress_rule_ids")
	require.Len(t, ingressRuleIDs, 7)
	for _, key := range []string{
		"https_from_vpc", "http_from_ipv6", "all_from_self", "mysql_from_app",
		"dns_from_prefix_list", "single_port_shorthand", "ephemeral_from_vpc",
	} {
		assert.Contains(t, ingressRuleIDs, key)
	}

	vpcAssociationIDs := terraform.OutputMap(t, terraformOptions, "vpc_association_ids")
	require.Len(t, vpcAssociationIDs, 1)
	assert.Contains(t, vpcAssociationIDs, "secondary")
}
