package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestVpcBasicExample applies examples/basic, asserts against real AWS state
// via the SDK (not just Terraform output), and destroys in a deferred
// cleanup even on assertion failure — per docs/coding-standards.md §8.
func TestVpcBasicExample(t *testing.T) {
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

	vpcID := terraform.Output(t, terraformOptions, "vpc_id")
	require.NotEmpty(t, vpcID)

	// --- Real AWS state assertions, not just TF output ---------------------
	vpc := aws.GetVpcById(t, vpcID, awsRegion)
	assert.Equal(t, "10.30.0.0/16", *vpc.CidrBlock)

	publicSubnetIDs := terraform.OutputMap(t, terraformOptions, "public_subnet_ids")
	privateSubnetIDs := terraform.OutputMap(t, terraformOptions, "private_subnet_ids")
	require.Len(t, publicSubnetIDs, 2, "expected 2 public subnets (one per AZ)")
	require.Len(t, privateSubnetIDs, 2, "expected 2 private subnets (one per AZ)")

	for az, subnetID := range publicSubnetIDs {
		subnet := aws.GetSubnetById(t, subnetID, awsRegion)
		assert.Equal(t, az, *subnet.AvailabilityZone)
		assert.False(t, *subnet.MapPublicIpOnLaunch, "public subnets should not auto-assign public IPs unless map_public_ip_on_launch is explicitly enabled")
	}

	// --- Single NAT Gateway strategy: exactly one NAT Gateway total --------
	natGatewayIDs := terraform.OutputMap(t, terraformOptions, "nat_gateway_ids")
	assert.Len(t, natGatewayIDs, 1, "nat_gateway_strategy = \"single\" should produce exactly one NAT Gateway")
}
